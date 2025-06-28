function Set-AppTrackingKey
{
  <#
      .SYNOPSIS
      Adds or Removes an Application Tracking Key from the Computer Registry
      .DESCRIPTION
      Adds or Removes an Application Tracking Key from the Computer Registry for the applications being Installed or Uninstalled.
      .PARAMETER Name
      
      .EXAMPLE
      
      .NOTES
      Author: Christopher Macnichol
      Version: 1.4
	  1.4 - 06/27/2025 - Christopher Macnichol - Updated for ADT 4.0 and updated Reg Location
      1.3 - 01/02/2020 - Christopher Macnichol - Added User Registry Option
      1.2 - Added Package Install Date
      Updated: 06/27/2025

  #>
  [CmdletBinding()]
  Param (

    [String] $Vendor = $adtSession.AppVendor,
    [String] $RegKeyName = $adtSession.AppName,
	[String] $Title = $adtSession.InstallTitle,
    [String] $Version = $adtSession.AppVersion,
    [String] $Arch = $adtSession.AppArch,
    [String] $Lang = $adtSession.AppLang,
    [String] $Revision = $adtSession.AppRevision,
    [String] $Packager = $appScriptAuthor,
    [String] $PackageCreationDate = $adtSession.AppScriptDate,
    [String] $ScriptVersion = $adtSession.AppScriptVersion,
	[String] $InstalledBy = $envUserName,
	[String] $DisplayName = $adtSession.ArpDisplayName,
	[String] $SourcePath = $ScriptParentPath,
    [String] $HKLMRegLocation = "HKCU:\SOFTWARE\SWD",
    [String] $HKCURegLocation = "HKLM:\SOFTWARE\SWD",
    [Switch] $User,
    [Switch] $Remove

  )

  begin
  {
  
      ## Get the name of this function and write header
      [string]${CmdletName} = $PSCmdlet.MyInvocation.MyCommand.Name
      Initialize-ADTFunction -Cmdlet $PSCmdlet -SessionState $ExecutionContext.SessionState
    
      # Set values
      If($User){ $FullRegKeyName = $HKCURegLocation + $RegKeyName }
      else { $FullRegKeyName = $HKLMRegLocation + $RegKeyName }

  }

  process
  {

	Try {

		if (!($Remove))
		{
			try {
				# Create Registry key
				Write-ADTLogEntry -Message "Creating Application Tracking Key for $RegKeyName" -Source ${CmdletName}

				Set-ADTRegistryKey -Key $FullRegKeyName

				# Write values
				Set-ADTRegistryKey -Key  $FullRegKeyName -Name 'Vendor' -Value $Vendor -Type String
				Set-ADTRegistryKey -Key  $FullRegKeyName -Name 'Application Name' -Value $RegKeyName -Type String
				Set-ADTRegistryKey -Key  $FullRegKeyName -Name 'Version' -Value $Version -Type String
				Set-ADTRegistryKey -Key  $FullRegKeyName -Name 'Architecture' -Value $Arch -Type String
				Set-ADTRegistryKey -Key  $FullRegKeyName -Name 'Language' -Value $Lang -Type String
				Set-ADTRegistryKey -Key  $FullRegKeyName -Name 'Package Revision' -Value $Revision -Type String
				Set-ADTRegistryKey -Key  $FullRegKeyName -Name 'Package Creation Date' -Value $PackageCreationDate -Type String
				Set-ADTRegistryKey -Key  $FullRegKeyName -Name 'Package Script Version' -Value $ScriptVersion -Type String
				Set-ADTRegistryKey -Key  $FullRegKeyName -Name 'Package Install Date' -Value $(Get-Date -Format 'yyyy-MM-dd') -Type String
				Set-ADTRegistryKey -Key  $FullRegKeyName -Name 'Packager' -Value $Packager -Type String
				Set-ADTRegistryKey -Key  $FullRegKeyName -Name 'Installed By' -Value $InstalledBy -Type String
				Set-ADTRegistryKey -Key  $FullRegKeyName -Name 'ARP DisplayName' -Value $DisplayName -Type String
				Set-ADTRegistryKey -Key  $FullRegKeyName -Name 'SourcePath' -Value $SourcePath -Type String
			}
			catch
			{
				Write-Error -ErrorRecord $_
			}
		}
		else
		{
			try {
				Write-ADTLogEntry -Message "Removing Application Tracking Key for $RegKeyName" -Source ${CmdletName}

				Remove-ADTRegistryKey -Key $FullRegKeyName -Recurse
				}
				catch
				{
					Write-Error -ErrorRecord $_
				}
		}

	  }
	  catch
	  {
		  Invoke-ADTFunctionErrorHandler -Cmdlet $PSCmdlet -SessionState $ExecutionContext.SessionState -ErrorRecord $_ -LogMessage "Failed to Write Registry Entries."
	  }

  }

  end
  {
    Complete-ADTFunction -Cmdlet $PSCmdlet

  }

}