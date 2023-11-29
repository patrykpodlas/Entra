<#
.SYNOPSIS
Shows differences in group memberships for two users, can be used to copy memberships over.

.DESCRIPTION
Shows differences in group memberships for two users, can be used to copy memberships over.

.PARAMETER userOne
Main user.

.PARAMETER userTwo
Secondary user.

.PARAMETER Copy
Used to copy memberships from userOne to userTwo

.EXAMPLE
Compare-MgUserMemberships -userOne <userOneUpn> -userTwo <userTwoUpn> -Copy

Shows differences in group memberships, then copies memberships of userOne over to userTwo.

Group name                               userOne@domain.com status userTwo@domain.com status Commonality
----------                               ---------------------------------------- ------------------------------------- -----------
All Users                                Member                                   Member                                Common

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
        [switch]$whatIf
    )

    begin {
        $userOneId = (Get-MgUser -Filter "UserPrincipalName eq '$($userOne)'").Id
        $userOneMemberships = (Get-MgUserMemberOf -UserId $userOneId | Select-Object -ExpandProperty AdditionalProperties).displayName

        $userTwoId = (Get-MgUser -Filter "UserPrincipalName eq '$($userTwo)'").Id
        $userTwoMemberships = (Get-MgUserMemberOf -UserId $userTwoId | Select-Object -ExpandProperty AdditionalProperties).displayName

        $allMemberships = $userOneMemberships + $userTwoMemberships | Sort-Object | Get-Unique
    }

    process {
        $results = @()

        foreach ($group in $allMemberships) {
            $userOneStatus = if ($userOneMemberships -contains $group) { "Member" } else { "Not a member" }
            $userTwoStatus = if ($userTwoMemberships -contains $group) { "Member" } else { "Not a member" }
            $commonStatus = if ($userOneStatus -eq "Member" -and $userTwoStatus -eq "Member") { "Common" } else { "Not common" }

            $results += [PSCustomObject]@{
                'Group name'      = $group
                "$userOne status" = $userOneStatus
                "$userTwo status" = $userTwoStatus
                'Commonality'     = $commonStatus
            }
        }

        if ($Copy) {
            foreach ($group in ($results | Where-Object -Property "$userTwo status" -eq "Not a member")) {
                Write-Output "Adding $UserTwo to group $($group."Group Name")"
                New-MgGroupMember -GroupId $group -DirectoryObjectId $userTwoId -WhatIf:$whatIf
            }
        }

        if ($Mirror) {
            <# Action to perform if the condition is true #>
        }
    }

    end {
        $results | Sort-Object -Property Commonality
    }
}

