<#
.SYNOPSIS
Shows differences in group memberships for two users, can be used to copy memberships over.

.DESCRIPTION
Shows differences in group memberships for two users, can be used to copy memberships over, either all or by index.

.PARAMETER userOne
Main user (the source or master user)

.PARAMETER userTwo
Secondary user (the user you want to copy the memberships over to)

.EXAMPLE
Compare-MgUserMemberships -userOne <userOneUpn> -userTwo <userTwoUpn>

Group name                               UserOne status                           userTwo status                        Commonality
----------                               ---------------------------------------- ------------------------------------- -----------
All Users                                Member                                   Member                                Common
Group - Administrators                   Member                                   Member                                Common
Group - Access                           Member                                   Member                                Common
Group - Production Access                Not a member                             Member                                Not common
Some Users                               Member                                   Not a member                          Not common

.EXAMPLE
Compare-MgUserMemberships -userOne <userOneUpn> -userTwo <userTwoUpn> -Copy

--- You can only copy the following groups:

Index groupName                                id                                   type      onPremisesSyncEnabled UserOne status                          userTwo status                          Commonality
----- ---------                                --                                   ----      --------------------- --------------------------------------- --------------------------------------- -----------
    3 <group1>                                 <groupID>                            {Unified}                       Member                                  Not a member                            Not common
    5 <group2>                                 <groupID>                            {}                              Member                                  Not a member                            Not common
    8 <group3>                                 <groupID>                                                            Member                                  Not a member                            Not common

--- Do you want to copy all or through an index? (All/Index): Index
Specify index from the table: 5
--- Adding userTwo to group '<group2>' with Id: <groupID>

--- Finished all operations.

.NOTES
General notes
#>
function Compare-MgUserMemberships {
    [CmdletBinding()]
    param (
        [string]$UserOne,
        [string]$UserTwo,
        [switch]$Copy,
        [switch]$Mirror,
        [switch]$WhatIf
    )

    begin {
        try {
            $userOneId = (Get-MgUser -Filter "UserPrincipalName eq '$($userOne)'").Id
            $userOneMemberships = (Get-MgUserMemberOf -UserId $userOneId | Select-Object Id, AdditionalProperties)
            $userOneMembershipsObject = @()
            foreach ($item in $userOneMemberships) {
                $customObject = [PSCustomObject]@{
                    displayName           = $item.AdditionalProperties.displayName
                    id                    = $item.Id
                    groupTypes            = $item.AdditionalProperties.groupTypes
                    onPremisesSyncEnabled = $item.AdditionalProperties.onPremisesSyncEnabled
                }
                $userOneMembershipsObject += $customObject
            }

            $userTwoId = (Get-MgUser -Filter "UserPrincipalName eq '$($userTwo)'").Id
            $userTwoMemberships = (Get-MgUserMemberOf -UserId $userTwoId | Select-Object Id, AdditionalProperties)
            $userTwoMembershipsObject = @()
            foreach ($item in $userTwoMemberships) {
                $customObject = [PSCustomObject]@{
                    displayName           = $item.AdditionalProperties.displayName
                    id                    = $item.Id
                    groupTypes            = $item.AdditionalProperties.groupTypes
                    onPremisesSyncEnabled = $item.AdditionalProperties.onPremisesSyncEnabled
                }
                $userTwoMembershipsObject += $customObject
            }

            $allMemberships = $userOneMembershipsObject + $userTwoMembershipsObject | Sort-Object displayName -Unique
        } catch {
            throw $_.Exception
        }
    }

    process {
        $results = @()
        $index = 1

        foreach ($group in $allMemberships) {
            $userOneStatus = if ($userOneMembershipsObject.displayName -contains $group.displayName) { "Member" } else { "Not a member" }
            $userTwoStatus = if ($userTwoMembershipsObject.displayName -contains $group.displayName) { "Member" } else { "Not a member" }
            $commonStatus = if ($userOneStatus -eq "Member" -and $userTwoStatus -eq "Member") { "Common" } else { "Not common" }

            $results += [PSCustomObject]@{
                'Index'                 = $index++
                'groupName'             = $group.displayName
                'id'                    = $group.id
                'type'                  = $group.groupTypes
                'onPremisesSyncEnabled' = $group.onPremisesSyncEnabled
                "$userOne status"       = $userOneStatus
                "$userTwo status"       = $userTwoStatus
                'Commonality'           = $commonStatus
            }
        }

        $results | Sort-Object -Property Commonality | Format-Table | Out-Host

        if ($Copy) {
            $filteredGroups = $results | Where-Object { ($_.type -notcontains "DynamicMembership") -and ($_."$userTwo status" -eq "Not a member") -and ($_.onPremisesSyncEnabled -ne "True") }
            if ($null -ne $filteredGroups) {
                Write-Host "--- You can only copy the following groups:" -ForegroundColor Yellow
                Write-Output $filteredGroups | Format-Table
                $readInput = Read-Host -Prompt "--- Do you want to copy all or through an index? (All/Index)"
                if ($readInput -eq "All") {
                    Write-Host "--- Copying all group memberships from user $userOne to $userTwo" -ForegroundColor Yellow
                    # Filter for groups the user is not a member of and also the group is not of dynamic memership type.
                    foreach ($group in $filteredGroups) {
                        Write-Host "    --- Adding $UserTwo to group $($group.groupName)" -ForegroundColor Yellow
                        New-MgGroupMember -GroupId $group.id -DirectoryObjectId $userTwoId -WhatIf:$WhatIf
                    }
                } elseif ($readInput -eq "Index") {
                    [int]$readInput = Read-Host -Prompt "Specify index from the table"
                    if ($readInput -in $filteredGroups.Index) {
                        $group = $($filteredGroups | Where-Object Index -eq $readInput | Select-Object Id, groupName)
                        Write-Host "--- Adding $UserTwo to group '$($group.groupName)' with Id: $($group.id)" -ForegroundColor Yellow
                        Get-MgGroup -GroupId $($group.id)
                        New-MgGroupMember -GroupId $($group.id) -DirectoryObjectId $userTwoId -WhatIf:$WhatIf
                    } else {
                        Write-Error "--- The user can't be added to the group(s), either the user is already a member of the group or the group is of dynamic membership type!"
                    }
                } else {
                    Write-Error "You must specify either All or Index!"
                    return
                }
            } else {
                Write-Host "--- There are no groups you can copy over." -ForegroundColor Yellow
                Write-Host ""
            }
        }
    }

    end {
        Write-Host "--- Finished all operations." -ForegroundColor Yellow
    }
}
