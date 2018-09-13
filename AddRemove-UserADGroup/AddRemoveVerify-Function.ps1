# Add User to AD Group
function Add-UserToGroup {
  param
  (
    [String]
    $User = $null,
      
    [String]
    $adGroup = $null,
      
    [string]
    $Action = 'Verify'
      
  )
      
  #region inputcheck
  if ($User -eq $null) 
  {
    Write-Log -Message 'User Input Empty, Skipping' -Level Warn;Return
  }

  # Set AD Group to default for action if not specified
  if (!($adGroup)) 
  {
    $adGroup = $Script:ADGroupI
    Write-Log -Message "No Active Directory Group Specified, Using default from Settings.ini: $adGroup" -Level Info
  }

  $group = Get-ADGroup -Identity $adGroup -Server $hbiServer
    
  #Getting user Details
  try 
  {
    $UserObj = Get-ADUser -Server $hbiServer -Identity $User -ErrorAction Stop
  }
  catch
  {
    Write-Log -Message "Error Getting User Details for: $User.  Skipping User" -Level Error
    return
  }
  #endregion inputcheck
      
      
  $SamAccount = $userObj.Name
  $groupName = $group.name
  [switch]$groupMember = $false

  Write-Log -Message "Checking if $($UserObj.name) is a member of $adGroup"
    
  $isMember = $(Get-ADUser -Server $hbiServer -Identity $userObj -Properties `
    MemberOf | Select-Object MemberOf -ExpandProperty MemberOf | Where-Object `
  {$_ -eq $Group.DistinguishedName} | Measure-Object | Select-Object -Expand Count)


  Switch ($Action) {

    Add {
    
      # Add User to Group
      Try 
      {
        if ($pscmdlet.ShouldProcess("$($group.name)", 'Adding User to Group'))
        {

          if ($isMember -eq '0') {
            Write-Log -Message "User is not a member of $($group.name), Adding User"
            Add-ADGroupMember -Identity $Group -Members $UserObj -Server $hbiServer -ErrorVariable addGrError -ErrorAction Stop   
            Write-Log -Message 'User Added Successfully'
            $result = 'Add'
          }
          else {
            Write-Log -Message "$($UserObj.SamAccountName) is already a member of Group: $($group.name), `
            Skipping Action" -Level Warn
          Return}
        }
      }
      catch
      {
        Write-Log -Message "Unable to Add $($UserObj.name) to $($group.name)" -Level Error
        Write-Log -Message $addGrError -Level Error
      }
    
    }

    Remove {
    
      # Remove User from Group
      Try 
      {
        if ($pscmdlet.ShouldProcess("$($group.name)", 'Removing User from Group'))
        {
          if ($isMember -eq '0') {
            Write-Log -Message "$($UserObj.SamAccountName) is NOT a member of Group: $($group.name), `
            Skipping Action" -Level Warn
          Return}
          else{
            Write-Log -Message "Found User in Group $($group.name), Removing User"
            Remove-ADGroupMember -Identity $Group -Members $UserObj -Server $hbiServer -ErrorVariable remGrError -ErrorAction Stop -Confirm:$false
            Write-Log -Message 'User Removed Successfully'
            $result = 'Remove'
            
          } # End Else
        } #End Should Process IF
      }
      catch
      {
        Write-Log -Message "Unable to Remove $($UserObj.name) from $($group.name)" -Level Warn
        Write-Log -Message $remGrError -Level Error
      }

    }
      
    Verify {
      if ($isMember -eq '0'){
        Write-Log -Message "User is not a member of $($group.name)"
        $groupMember = 'False'
      }
      elseif($isMember -gt '0'){
        Write-Log -Message "User exists in group: $($group.name)"
        $groupMember = 'True'
      }
      
    }
    
  }
  # Create Array to Store results
  $member = [PSCustomObject]@{
    Member = $(If($isMember -eq '0'){'True'}else{'False'})
    Result = $result
  }#EndPSCustomObject
  
  Return $member
} # End Fuction Add user to Group
