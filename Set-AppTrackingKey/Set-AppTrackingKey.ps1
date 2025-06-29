function Set-AppTrackingKey {
    <#
        .SYNOPSIS
        Adds or removes an application tracking key from the computer registry.
        
        .DESCRIPTION
        This function creates or removes registry entries that track application installations
        and uninstallations. It stores metadata about the application including version,
        architecture, installation date, and other relevant information for deployment tracking.
        
        .PARAMETER Vendor
        The vendor/publisher name of the application. Defaults to $adtSession.AppVendor.
        
        .PARAMETER RegKeyName
        The registry key name for the application. Defaults to $adtSession.AppName.
        
        .PARAMETER Title
        The installation title. Defaults to $adtSession.InstallTitle.
        
        .PARAMETER Version
        The application version. Defaults to $adtSession.AppVersion.
        
        .PARAMETER Arch
        The application architecture (x86, x64, etc.). Defaults to $adtSession.AppArch.
        
        .PARAMETER Lang
        The application language. Defaults to $adtSession.AppLang.
        
        .PARAMETER Revision
        The package revision number. Defaults to $adtSession.AppRevision.
        
        .PARAMETER Packager
        The name of the person who created the package. Defaults to $appScriptAuthor.
        
        .PARAMETER PackageCreationDate
        The date the package was created. Defaults to $adtSession.AppScriptDate.
        
        .PARAMETER ScriptVersion
        The version of the deployment script. Defaults to $adtSession.AppScriptVersion.
        
        .PARAMETER InstalledBy
        The user who installed the application. Defaults to $envUserName.
        
        .PARAMETER DisplayName
        The display name shown in Add/Remove Programs. Defaults to $adtSession.ArpDisplayName.
        
        .PARAMETER SourcePath
        The source path of the installation files. Defaults to $ScriptParentPath.
        
        .PARAMETER HKLMRegLocation
        The HKLM registry location for system-wide tracking. Default: "HKLM:\SOFTWARE\SWD"
        
        .PARAMETER HKCURegLocation
        The HKCU registry location for user-specific tracking. Default: "HKCU:\SOFTWARE\SWD"
        
        .PARAMETER User
        Switch to create the tracking key in HKCU instead of HKLM for user-specific installations.
        
        .PARAMETER Remove
        Switch to remove the tracking key instead of creating it.
        
        .EXAMPLE
        Set-AppTrackingKey
        Creates an application tracking registry key using default ADT session values.
        
        .EXAMPLE
        Set-AppTrackingKey -Vendor "Microsoft" -RegKeyName "Office365" -Version "16.0.1"
        Creates a tracking key for Microsoft Office 365 with specific values.
        
        .EXAMPLE
        Set-AppTrackingKey -RegKeyName "MyApp" -User
        Creates a user-specific tracking key in HKCU for "MyApp".
        
        .EXAMPLE
        Set-AppTrackingKey -RegKeyName "OldApp" -Remove
        Removes the tracking key for "OldApp".
        
        .NOTES
        Author: Christopher Macnichol
        Version: 1.5
        1.5 - 06/29/2025 - Code review improvements - Better error handling, parameter validation, comments
        1.4 - 06/27/2025 - Christopher Macnichol - Updated for ADT 4.0 and updated Reg Location
        1.3 - 01/02/2020 - Christopher Macnichol - Added User Registry Option
        1.2 - Added Package Install Date
        Updated: 06/29/2025
        
        .LINK
        https://psappdeploytoolkit.com/
    #>
    
    [CmdletBinding(SupportsShouldProcess)]
    param (
        [Parameter(ValueFromPipelineByPropertyName)]
        [ValidateNotNullOrEmpty()]
        [string]$Vendor = $adtSession.AppVendor,
        
        [Parameter(ValueFromPipelineByPropertyName)]
        [ValidateNotNullOrEmpty()]
        [string]$RegKeyName = $adtSession.AppName,
        
        [Parameter(ValueFromPipelineByPropertyName)]
        [string]$Title = $adtSession.InstallTitle,
        
        [Parameter(ValueFromPipelineByPropertyName)]
        [string]$Version = $adtSession.AppVersion,
        
        [Parameter(ValueFromPipelineByPropertyName)]
        [ValidateSet('x86', 'x64', 'ARM64', 'Any CPU', '')]
        [string]$Arch = $adtSession.AppArch,
        
        [Parameter(ValueFromPipelineByPropertyName)]
        [string]$Lang = $adtSession.AppLang,
        
        [Parameter(ValueFromPipelineByPropertyName)]
        [string]$Revision = $adtSession.AppRevision,
        
        [Parameter(ValueFromPipelineByPropertyName)]
        [string]$Packager = $appScriptAuthor,
        
        [Parameter(ValueFromPipelineByPropertyName)]
        [string]$PackageCreationDate = $adtSession.AppScriptDate,
        
        [Parameter(ValueFromPipelineByPropertyName)]
        [string]$ScriptVersion = $adtSession.AppScriptVersion,
        
        [Parameter(ValueFromPipelineByPropertyName)]
        [string]$InstalledBy = $envUserName,
        
        [Parameter(ValueFromPipelineByPropertyName)]
        [string]$DisplayName = $adtSession.ArpDisplayName,
        
        [Parameter(ValueFromPipelineByPropertyName)]
        [ValidateScript({
            if ($_ -and -not (Test-Path $_ -IsValid)) {
                throw "Invalid path format: $_"
            }
            return $true
        })]
        [string]$SourcePath = $ScriptParentPath,
        
        [Parameter()]
        [ValidatePattern('^HK(LM|CU):\\')]
        [string]$HKLMRegLocation = "HKLM:\SOFTWARE\SWD",
        
        [Parameter()]
        [ValidatePattern('^HK(LM|CU):\\')]
        [string]$HKCURegLocation = "HKCU:\SOFTWARE\SWD",
        
        [Parameter()]
        [switch]$User,
        
        [Parameter()]
        [switch]$Remove
    )

    begin {
        # Get the name of this function and write header
        [string]${CmdletName} = $PSCmdlet.MyInvocation.MyCommand.Name
        Initialize-ADTFunction -Cmdlet $PSCmdlet -SessionState $ExecutionContext.SessionState
        
        # Validate required parameters when not removing
        if (-not $Remove) {
            if ([string]::IsNullOrWhiteSpace($RegKeyName)) {
                throw "RegKeyName cannot be null or empty when creating a tracking key."
            }
            if ([string]::IsNullOrWhiteSpace($Vendor)) {
                throw "Vendor cannot be null or empty when creating a tracking key."
            }
        }
        
        # Determine the full registry key path based on User switch
        if ($User) {
            $FullRegKeyName = Join-Path $HKCURegLocation $RegKeyName
            Write-ADTLogEntry -Message "Using HKCU registry location for user-specific tracking" -Source ${CmdletName}
        }
        else {
            $FullRegKeyName = Join-Path $HKLMRegLocation $RegKeyName
            Write-ADTLogEntry -Message "Using HKLM registry location for system-wide tracking" -Source ${CmdletName}
        }
        
        Write-ADTLogEntry -Message "Target registry key: $FullRegKeyName" -Source ${CmdletName}
    }

    process {
        try {
            if ($Remove) {
                # Remove the application tracking key
                if ($PSCmdlet.ShouldProcess($FullRegKeyName, "Remove Registry Key")) {
                    Write-ADTLogEntry -Message "Removing Application Tracking Key for '$RegKeyName'" -Source ${CmdletName}
                    
                    if (Test-Path $FullRegKeyName) {
                        Remove-ADTRegistryKey -Key $FullRegKeyName -Recurse
                        Write-ADTLogEntry -Message "Successfully removed tracking key for '$RegKeyName'" -Source ${CmdletName}
                    }
                    else {
                        Write-ADTLogEntry -Message "Tracking key for '$RegKeyName' does not exist, no action needed" -Source ${CmdletName} -Severity 2
                    }
                }
            }
            else {
                # Create the application tracking key
                if ($PSCmdlet.ShouldProcess($FullRegKeyName, "Create Registry Key")) {
                    Write-ADTLogEntry -Message "Creating Application Tracking Key for '$RegKeyName'" -Source ${CmdletName}

                    # Create the main registry key
                    Set-ADTRegistryKey -Key $FullRegKeyName

                    # Define registry values to write
                    $registryValues = @{
                        'Vendor'                    = $Vendor
                        'Application Name'          = $RegKeyName
                        'Title'                     = $Title
                        'Version'                   = $Version
                        'Architecture'              = $Arch
                        'Language'                  = $Lang
                        'Package Revision'          = $Revision
                        'Package Creation Date'     = $PackageCreationDate
                        'Package Script Version'    = $ScriptVersion
                        'Package Install Date'      = Get-Date -Format 'yyyy-MM-dd HH:mm:ss'
                        'Packager'                  = $Packager
                        'Installed By'              = $InstalledBy
                        'ARP DisplayName'           = $DisplayName
                        'Source Path'               = $SourcePath
                        'Install Method'            = if ($User) { 'User' } else { 'System' }
                    }

                    # Write each registry value, skipping empty ones
                    foreach ($valueName in $registryValues.Keys) {
                        $value = $registryValues[$valueName]
                        if (-not [string]::IsNullOrWhiteSpace($value)) {
                            Set-ADTRegistryKey -Key $FullRegKeyName -Name $valueName -Value $value -Type String
                            Write-ADTLogEntry -Message "Set registry value '$valueName' = '$value'" -Source ${CmdletName} -DebugMessage
                        }
                    }

                    Write-ADTLogEntry -Message "Successfully created tracking key for '$RegKeyName'" -Source ${CmdletName}
                }
            }
        }
        catch {
            $errorMessage = if ($Remove) {
                "Failed to remove Application Tracking Key for '$RegKeyName': $($_.Exception.Message)"
            }
            else {
                "Failed to create Application Tracking Key for '$RegKeyName': $($_.Exception.Message)"
            }
            
            Invoke-ADTFunctionErrorHandler -Cmdlet $PSCmdlet -SessionState $ExecutionContext.SessionState -ErrorRecord $_ -LogMessage $errorMessage
        }
    }

    end {
        Complete-ADTFunction -Cmdlet $PSCmdlet
    }
}