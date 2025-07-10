# Enhanced Tanium Platform Script - AutoPilot Deploy Tagging with Forced Checkin
# Version: 2.1
# This script tags the computer with AutoPilotDeploy information and forces a Tanium checkin

#Requires -RunAsAdministrator
[CmdletBinding()]
param(
    [ValidateNotNullOrEmpty()]
    [string]$DeploymentTag = "AutoPilot",
    
    [ValidateSet("PRODUCTION", "STAGING", "DEVELOPMENT", "TEST")]
    [string]$Environment = "PRODUCTION",
    
    [switch]$IncludeTimestamp = $true,
    [switch]$VerboseLogging = $false,
    [switch]$Force = $false,
    [switch]$Rollback = $false
)

# Script configuration
$script:Config = @{
    RegPath = "HKLM:\SOFTWARE\SWD\AutopilotDeploy"
    TaniumPaths = @(
        "C:\Program Files (x86)\Tanium\Tanium Client\TaniumClient.exe",
        "C:\Program Files\Tanium\Tanium Client\TaniumClient.exe"
    )
    TempPath = "C:\Windows\Temp"
    EventLogSource = "Tanium AutoPilot Script"
    MaxRetries = 3
    RetryDelay = 2
    ScriptVersion = "2.1"
}

# Initialize event log source
function Initialize-EventLogSource {
    try {
        if (-not [System.Diagnostics.EventLog]::SourceExists($script:Config.EventLogSource)) {
            New-EventLog -LogName "Application" -Source $script:Config.EventLogSource
            Write-Output "Created event log source: $($script:Config.EventLogSource)"
        }
    } catch {
        Write-Warning "Could not create event log source: $($_.Exception.Message)"
    }
}

# Enhanced logging function
function Write-Log {
    param(
        [string]$Message,
        [ValidateSet("INFO", "WARNING", "ERROR", "DEBUG")]
        [string]$Level = "INFO"
    )
    
    $timestamp = Get-Date -Format "yyyy-MM-dd HH:mm:ss"
    $logMessage = "[$timestamp] [$Level] $Message"
    
    # Console output
    switch ($Level) {
        "ERROR" { Write-Error $logMessage }
        "WARNING" { Write-Warning $logMessage }
        "DEBUG" { if ($VerboseLogging) { Write-Verbose $logMessage -Verbose } }
        default { 
            if ($VerboseLogging -or $Level -eq "INFO") { 
                Write-Host $logMessage -ForegroundColor $(
                    switch ($Level) {
                        "INFO" { "Green" }
                        "WARNING" { "Yellow" }
                        "ERROR" { "Red" }
                        default { "White" }
                    }
                )
            }
        }
    }
    
    # Event log output
    try {
        $eventType = switch ($Level) {
            "ERROR" { "Error" }
            "WARNING" { "Warning" }
            default { "Information" }
        }
        
        Write-EventLog -LogName "Application" -Source $script:Config.EventLogSource -EventId 1001 -EntryType $eventType -Message $logMessage -ErrorAction SilentlyContinue
    } catch {
        # Continue silently if event log fails
    }
}

# Retry logic wrapper
function Invoke-WithRetry {
    param(
        [scriptblock]$ScriptBlock,
        [int]$MaxRetries = $script:Config.MaxRetries,
        [int]$DelaySeconds = $script:Config.RetryDelay,
        [string]$OperationName = "Operation"
    )
    
    for ($i = 1; $i -le $MaxRetries; $i++) {
        try {
            Write-Log "Attempting $OperationName (attempt $i of $MaxRetries)" -Level "DEBUG"
            $result = & $ScriptBlock
            if ($result) { 
                Write-Log "$OperationName succeeded on attempt $i" -Level "DEBUG"
                return $result 
            }
        } catch {
            Write-Log "$OperationName attempt $i failed: $($_.Exception.Message)" -Level "WARNING"
        }
        
        if ($i -lt $MaxRetries) {
            Write-Log "Waiting $DelaySeconds seconds before retry..." -Level "DEBUG"
            Start-Sleep -Seconds $DelaySeconds
        }
    }
    
    Write-Log "$OperationName failed after $MaxRetries attempts" -Level "ERROR"
    return $false
}

# Enhanced prerequisite checks
function Test-Prerequisites {
    Write-Log "Checking prerequisites..." -Level "INFO"
    $issues = @()
    
    # Check if running as admin
    if (-not ([Security.Principal.WindowsPrincipal][Security.Principal.WindowsIdentity]::GetCurrent()).IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator)) {
        $issues += "Script must run as Administrator"
    }
    
    # Check if Tanium client service exists
    $taniumService = Get-Service -Name "Tanium Client" -ErrorAction SilentlyContinue
    if (-not $taniumService) {
        $issues += "Tanium Client service not found"
    } elseif ($taniumService.Status -ne 'Running') {
        Write-Log "Tanium Client service is not running (Status: $($taniumService.Status))" -Level "WARNING"
    }
    
    # Check registry access
    try {
        $null = Get-ItemProperty -Path "HKLM:\SOFTWARE\" -ErrorAction Stop
    } catch {
        $issues += "Cannot access HKLM registry: $($_.Exception.Message)"
    }
    
    # Check temp directory access
    try {
        $testFile = Join-Path $script:Config.TempPath "test_$(Get-Random).tmp"
        "test" | Out-File -FilePath $testFile -Force
        Remove-Item -Path $testFile -Force
    } catch {
        $issues += "Cannot write to temp directory: $($_.Exception.Message)"
    }
    
    if ($issues.Count -gt 0) {
        foreach ($issue in $issues) {
            Write-Log $issue -Level "ERROR"
        }
        return $false
    }
    
    Write-Log "All prerequisites passed" -Level "INFO"
    return $true
}

# Build tag value with proper formatting
function Build-TagValue {
    param(
        [string]$Tag,
        [string]$Environment,
        [bool]$IncludeTimestamp
    )
    
    $tagValue = $Tag
    
    if ($Environment) {
        $tagValue += "_$Environment"
    }
    
    if ($IncludeTimestamp) {
        $timestamp = Get-Date -Format "yyyy-MM-dd_HH-mm-ss"
        $tagValue += "_$timestamp"
    }
    
    return $tagValue
}

# Get Tanium client path
function Get-TaniumClientPath {
    foreach ($path in $script:Config.TaniumPaths) {
        if (Test-Path $path) { 
            Write-Log "Found Tanium client at: $path" -Level "DEBUG"
            return $path 
        }
    }
    
    # Try to get from service
    try {
        $service = Get-WmiObject -Query "SELECT PathName FROM Win32_Service WHERE Name='Tanium Client'" -ErrorAction Stop
        if ($service -and $service.PathName) {
            $path = $service.PathName -replace '"', '' -replace '\s+start.*$', ''
            if (Test-Path $path) { 
                Write-Log "Found Tanium client via service: $path" -Level "DEBUG"
                return $path 
            }
        }
    } catch {
        Write-Log "Could not query Tanium service path: $($_.Exception.Message)" -Level "DEBUG"
    }
    
    Write-Log "Tanium client executable not found" -Level "WARNING"
    return $null
}

# Enhanced Tanium checkin function
function Invoke-TaniumCheckin {
    [CmdletBinding()]
    param()
    
    Write-Log "Initiating Tanium checkin..." -Level "INFO"
    
    return Invoke-WithRetry -OperationName "Tanium Checkin" -ScriptBlock {
        # Check if Tanium service is running
        $service = Get-Service -Name "Tanium Client" -ErrorAction SilentlyContinue
        if (-not $service) {
            Write-Log "Tanium Client service not found" -Level "ERROR"
            return $false
        }
        
        if ($service.Status -ne 'Running') {
            Write-Log "Tanium Client service is not running, attempting to start..." -Level "WARNING"
            try {
                Start-Service -Name "Tanium Client" -ErrorAction Stop
                Start-Sleep -Seconds 3
            } catch {
                Write-Log "Could not start Tanium Client service: $($_.Exception.Message)" -Level "ERROR"
                return $false
            }
        }
        
        # Method 1: Try service restart (most reliable)
        try {
            Write-Log "Attempting Tanium checkin via service restart..." -Level "DEBUG"
            Restart-Service -Name "Tanium Client" -Force -ErrorAction Stop
            Start-Sleep -Seconds 5
            Write-Log "Tanium service restarted successfully" -Level "INFO"
            return $true
        } catch {
            Write-Log "Service restart failed: $($_.Exception.Message)" -Level "WARNING"
        }
        
        # Method 2: Try executable method
        $taniumClient = Get-TaniumClientPath
        if ($taniumClient) {
            try {
                Write-Log "Attempting Tanium checkin via executable..." -Level "DEBUG"
                $result = Start-Process -FilePath $taniumClient -ArgumentList "checkin" -WindowStyle Hidden -PassThru -Wait -ErrorAction Stop
                
                if ($result.ExitCode -eq 0) {
                    Write-Log "Tanium checkin via executable succeeded" -Level "INFO"
                    return $true
                } else {
                    Write-Log "Tanium checkin returned exit code: $($result.ExitCode)" -Level "WARNING"
                }
            } catch {
                Write-Log "Executable checkin failed: $($_.Exception.Message)" -Level "WARNING"
            }
        }
        
        return $false
    }
}

# Enhanced custom tag setting
function Set-TaniumCustomTag {
    param([string]$TagValue = "AutoPilot")
    
    Write-Log "Setting Tanium custom tag: $TagValue" -Level "INFO"
    
    return Invoke-WithRetry -OperationName "Set Tanium Custom Tag" -ScriptBlock {
        # Method 1: Direct registry approach (if supported)
        $taniumRegPath = "HKLM:\SOFTWARE\WOW6432Node\Tanium\Tanium Client\Sensor Data\Tags"
        
        try {
            if (Test-Path $taniumRegPath) {
                Set-ItemProperty -Path $taniumRegPath -Name "AutoPilot" -Value $TagValue -Force -ErrorAction Stop
                Write-Log "Set Tanium custom tag via registry" -Level "INFO"
                return $true
            }
        } catch {
            Write-Log "Registry method failed: $($_.Exception.Message)" -Level "DEBUG"
        }
        
        # Method 2: WMI approach (if available)
        try {
            $taniumClient = Get-TaniumClientPath
            if ($taniumClient) {
                $wmiResult = Invoke-WmiMethod -Class "Win32_Process" -Name "Create" -ArgumentList "$taniumClient settag AutoPilot=$TagValue" -ErrorAction Stop
                if ($wmiResult.ReturnValue -eq 0) {
                    Write-Log "Set Tanium custom tag via WMI" -Level "INFO"
                    return $true
                }
            }
        } catch {
            Write-Log "WMI method failed: $($_.Exception.Message)" -Level "DEBUG"
        }
        
        # Method 3: Fallback to marker file approach
        try {
            $tagData = @{
                "TaniumCustomTag" = $TagValue
                "SetTimestamp" = Get-Date -Format "yyyy-MM-dd HH:mm:ss"
                "ComputerName" = $env:COMPUTERNAME
                "Status" = "DEPLOYMENT_COMPLETE"
            }
            
            $markerFile = Join-Path $script:Config.TempPath "tanium_autopilot_marker.txt"
            $tagData | ConvertTo-Json | Out-File -FilePath $markerFile -Force -ErrorAction Stop
            
            # Also create queue file for scheduled task pickup
            $queueFile = Join-Path $script:Config.TempPath "tanium_tag_queue.txt"
            Add-Content -Path $queueFile -Value "$TagValue|$(Get-Date -Format 'yyyy-MM-dd HH:mm:ss')" -Force -ErrorAction Stop
            
            Write-Log "Created Tanium custom tag marker files" -Level "INFO"
            return $true
            
        } catch {
            Write-Log "Marker file method failed: $($_.Exception.Message)" -Level "WARNING"
            return $false
        }
    }
}

# Enhanced registry tag setting
function Set-AutoPilotTag {
    param(
        [string]$Tag,
        [string]$Env,
        [bool]$IncludeTime
    )
    
    Write-Log "Setting AutoPilot registry tags..." -Level "INFO"
    
    return Invoke-WithRetry -OperationName "Set Registry Tags" -ScriptBlock {
        try {
            # Create registry path if it doesn't exist
            if (-not (Test-Path $script:Config.RegPath)) {
                $null = New-Item -Path $script:Config.RegPath -Force -ErrorAction Stop
                Write-Log "Created registry path: $($script:Config.RegPath)" -Level "DEBUG"
            }
            
            # Build tag value
            $tagValue = Build-TagValue -Tag $Tag -Environment $Env -IncludeTimestamp $IncludeTime
            
            # Prepare all registry properties
            $properties = @{
                "DeploymentTag" = $tagValue
                "DeploymentTimestamp" = (Get-Date -Format "yyyy-MM-dd HH:mm:ss")
                "Environment" = $Env
                "ComputerName" = $env:COMPUTERNAME
                "UserName" = $env:USERNAME
                "DeploymentPhase" = "AUTOPILOT_COMPLETE"
                "ScriptVersion" = $script:Config.ScriptVersion
                "DeploymentMethod" = "AUTOPILOT_PLATFORM_SCRIPT"
                "LastCheckin" = (Get-Date -Format "yyyy-MM-dd HH:mm:ss")
            }
            
            # Set basic properties
            foreach ($prop in $properties.GetEnumerator()) {
                Set-ItemProperty -Path $script:Config.RegPath -Name $prop.Key -Value $prop.Value -Force -ErrorAction Stop
            }
            
            # Add system information
            Add-SystemInformation
            
            # Add Azure AD information
            Add-AzureADInformation
            
            # Add AutoPilot specific information
            Add-AutoPilotInformation
            
            # Create deployment summary
            Create-DeploymentSummary -TagValue $tagValue -Environment $Env
            
            Write-Log "Successfully set all AutoPilot registry tags" -Level "INFO"
            return $true
            
        } catch {
            Write-Log "Failed to set registry tags: $($_.Exception.Message)" -Level "ERROR"
            return $false
        }
    }
}

# Add system information to registry
function Add-SystemInformation {
    try {
        $osInfo = Get-WmiObject -Class Win32_OperatingSystem -ErrorAction Stop
        
        Set-ItemProperty -Path $script:Config.RegPath -Name "OSVersion" -Value $osInfo.Version -Force -ErrorAction Stop
        Set-ItemProperty -Path $script:Config.RegPath -Name "OSCaption" -Value $osInfo.Caption -Force -ErrorAction Stop
        Set-ItemProperty -Path $script:Config.RegPath -Name "OSArchitecture" -Value $osInfo.OSArchitecture -Force -ErrorAction Stop
        Set-ItemProperty -Path $script:Config.RegPath -Name "Domain" -Value $env:USERDOMAIN -Force -ErrorAction Stop
        Set-ItemProperty -Path $script:Config.RegPath -Name "SerialNumber" -Value (Get-WmiObject -Class Win32_BIOS).SerialNumber -Force -ErrorAction Stop
        
        Write-Log "Added system information to registry" -Level "DEBUG"
    } catch {
        Write-Log "Could not add system information: $($_.Exception.Message)" -Level "WARNING"
    }
}

# Add Azure AD information to registry
function Add-AzureADInformation {
    try {
        $azureAdInfo = dsregcmd /status 2>$null
        if ($azureAdInfo) {
            $joinStatus = if ($azureAdInfo -match "AzureAdJoined\s*:\s*YES") { "YES" } else { "NO" }
            $deviceId = if ($azureAdInfo -match "DeviceId\s*:\s*([a-f0-9-]+)") { $matches[1] } else { "UNKNOWN" }
            $tenantId = if ($azureAdInfo -match "TenantId\s*:\s*([a-f0-9-]+)") { $matches[1] } else { "UNKNOWN" }
            
            Set-ItemProperty -Path $script:Config.RegPath -Name "AzureAdJoined" -Value $joinStatus -Force -ErrorAction Stop
            Set-ItemProperty -Path $script:Config.RegPath -Name "AzureDeviceId" -Value $deviceId -Force -ErrorAction Stop
            Set-ItemProperty -Path $script:Config.RegPath -Name "AzureTenantId" -Value $tenantId -Force -ErrorAction Stop
            
            Write-Log "Added Azure AD information to registry" -Level "DEBUG"
        } else {
            Set-ItemProperty -Path $script:Config.RegPath -Name "AzureAdJoined" -Value "UNKNOWN" -Force -ErrorAction Stop
        }
    } catch {
        Write-Log "Could not add Azure AD information: $($_.Exception.Message)" -Level "WARNING"
    }
}

# Add AutoPilot specific information to registry
function Add-AutoPilotInformation {
    try {
        $autopilotPath = "HKLM:\SOFTWARE\Microsoft\Provisioning\Diagnostics\Autopilot"
        $autopilotInfo = Get-ItemProperty -Path $autopilotPath -ErrorAction SilentlyContinue
        
        if ($autopilotInfo) {
            if ($autopilotInfo.ProfileName) {
                Set-ItemProperty -Path $script:Config.RegPath -Name "AutopilotProfileName" -Value $autopilotInfo.ProfileName -Force -ErrorAction Stop
            }
            if ($autopilotInfo.DeploymentMode) {
                Set-ItemProperty -Path $script:Config.RegPath -Name "AutopilotDeploymentMode" -Value $autopilotInfo.DeploymentMode -Force -ErrorAction Stop
            }
            
            Write-Log "Added AutoPilot information to registry" -Level "DEBUG"
        }
    } catch {
        Write-Log "Could not add AutoPilot information: $($_.Exception.Message)" -Level "WARNING"
    }
}

# Create deployment summary
function Create-DeploymentSummary {
    param(
        [string]$TagValue,
        [string]$Environment
    )
    
    try {
        # Get current registry values
        $regData = Get-ItemProperty -Path $script:Config.RegPath -ErrorAction Stop
        
        # Create summary object
        $summaryInfo = @{
            "DeploymentTag" = $TagValue
            "Environment" = $Environment
            "Timestamp" = $regData.DeploymentTimestamp
            "AzureAdJoined" = $regData.AzureAdJoined
            "TaniumCustomTag" = "AutoPilot"
            "ComputerName" = $env:COMPUTERNAME
            "ScriptVersion" = $script:Config.ScriptVersion
        }
        
        # Save as JSON in registry
        $summaryJson = $summaryInfo | ConvertTo-Json -Compress
        Set-ItemProperty -Path $script:Config.RegPath -Name "DeploymentSummary" -Value $summaryJson -Force -ErrorAction Stop
        
        # Create summary text file
        $summaryFile = Join-Path $script:Config.TempPath "autopilot_deployment_summary.txt"
        $summaryText = @"
AutoPilot Deployment Summary
===========================
Deployment Tag: $($summaryInfo.DeploymentTag)
Environment: $($summaryInfo.Environment)
Timestamp: $($summaryInfo.Timestamp)
Computer: $($summaryInfo.ComputerName)
Domain: $env:USERDOMAIN
Azure AD Joined: $($summaryInfo.AzureAdJoined)
Tanium Custom Tag: AutoPilot
Script Version: $($summaryInfo.ScriptVersion)
Generated: $(Get-Date -Format "yyyy-MM-dd HH:mm:ss")
"@
        
        $summaryText | Out-File -FilePath $summaryFile -Force -ErrorAction Stop
        Write-Log "Created deployment summary file: $summaryFile" -Level "INFO"
        
    } catch {
        Write-Log "Could not create deployment summary: $($_.Exception.Message)" -Level "WARNING"
    }
}

# Enhanced tag verification
function Test-AutoPilotTag {
    Write-Log "Verifying AutoPilot tags..." -Level "INFO"
    
    $results = @{
        "RegistryTag" = $false
        "TaniumMarker" = $false
        "Summary" = $false
    }
    
    try {
        # Check registry tag
        if (Test-Path $script:Config.RegPath) {
            $regTag = Get-ItemProperty -Path $script:Config.RegPath -Name "DeploymentTag" -ErrorAction SilentlyContinue
            if ($regTag -and $regTag.DeploymentTag) {
                Write-Log "Verified registry AutoPilot tag: $($regTag.DeploymentTag)" -Level "INFO"
                $results.RegistryTag = $true
            }
        }
        
        # Check Tanium marker files
        $markerFile = Join-Path $script:Config.TempPath "tanium_autopilot_marker.txt"
        $queueFile = Join-Path $script:Config.TempPath "tanium_tag_queue.txt"
        
        if (Test-Path $markerFile) {
            Write-Log "Verified Tanium marker file exists" -Level "INFO"
            $results.TaniumMarker = $true
        }
        
        if (Test-Path $queueFile) {
            $queueContent = Get-Content $queueFile -ErrorAction SilentlyContinue
            if ($queueContent -match "AutoPilot") {
                Write-Log "Verified AutoPilot tag in Tanium queue" -Level "INFO"
                $results.TaniumMarker = $true
            }
        }
        
        # Check summary file
        $summaryFile = Join-Path $script:Config.TempPath "autopilot_deployment_summary.txt"
        if (Test-Path $summaryFile) {
            $results.Summary = $true
        }
        
        $overallSuccess = $results.RegistryTag -and $results.TaniumMarker
        
        if ($overallSuccess) {
            Write-Log "All AutoPilot tags verified successfully" -Level "INFO"
        } else {
            Write-Log "Tag verification failed - Registry: $($results.RegistryTag), Tanium: $($results.TaniumMarker)" -Level "WARNING"
        }
        
        return $overallSuccess
        
    } catch {
        Write-Log "Error verifying AutoPilot tags: $($_.Exception.Message)" -Level "ERROR"
        return $false
    }
}

# Rollback function
function Remove-AutoPilotTag {
    Write-Log "Removing AutoPilot tags..." -Level "INFO"
    
    try {
        # Remove registry entries
        if (Test-Path $script:Config.RegPath) {
            Remove-Item -Path $script:Config.RegPath -Recurse -Force -ErrorAction Stop
            Write-Log "Removed AutoPilot registry entries" -Level "INFO"
        }
        
        # Clean up temp files
        $tempFiles = @(
            "tanium_autopilot_marker.txt",
            "tanium_tag_queue.txt",
            "autopilot_deployment_summary.txt"
        )
        
        foreach ($file in $tempFiles) {
            $fullPath = Join-Path $script:Config.TempPath $file
            if (Test-Path $fullPath) {
                Remove-Item -Path $fullPath -Force -ErrorAction SilentlyContinue
                Write-Log "Removed file: $fullPath" -Level "DEBUG"
            }
        }
        
        Write-Log "AutoPilot tag removal completed successfully" -Level "INFO"
        return $true
        
    } catch {
        Write-Log "Error removing AutoPilot tags: $($_.Exception.Message)" -Level "ERROR"
        return $false
    }
}

# Main execution function
function Main {
    try {
        # Initialize logging
        Initialize-EventLogSource
        
        Write-Log "Starting Enhanced AutoPilot Deploy tagging script v$($script:Config.ScriptVersion)" -Level "INFO"
        Write-Log "Parameters: Tag=$DeploymentTag, Environment=$Environment, IncludeTimestamp=$IncludeTimestamp, Force=$Force, Rollback=$Rollback" -Level "INFO"
        
        # Handle rollback
        if ($Rollback) {
            $rollbackResult = Remove-AutoPilotTag
            if ($rollbackResult) {
                Write-Log "Rollback completed successfully" -Level "INFO"
                return 0
            } else {
                Write-Log "Rollback failed" -Level "ERROR"
                return 10
            }
        }
        
        # Check prerequisites
        if (-not (Test-Prerequisites)) {
            Write-Log "Prerequisites check failed" -Level "ERROR"
            return 4
        }
        
        # Check if already tagged (unless forced)
        if (-not $Force -and (Test-Path $script:Config.RegPath)) {
            $existingTag = Get-ItemProperty -Path $script:Config.RegPath -Name "DeploymentTag" -ErrorAction SilentlyContinue
            if ($existingTag) {
                Write-Log "AutoPilot tag already exists: $($existingTag.DeploymentTag). Use -Force to overwrite." -Level "WARNING"
                return 5
            }
        }
        
        # Set the AutoPilot tags
        $tagResult = Set-AutoPilotTag -Tag $DeploymentTag -Env $Environment -IncludeTime $IncludeTimestamp
        
        if ($tagResult) {
            # Set Tanium custom tag
            $taniumTagResult = Set-TaniumCustomTag -TagValue "AutoPilot"
            
            # Verify tags were set
            Start-Sleep -Seconds 2
            $verifyResult = Test-AutoPilotTag
            
            if ($verifyResult) {
                # Force Tanium checkin
                Write-Log "Forcing Tanium checkin..." -Level "INFO"
                $checkinResult = Invoke-TaniumCheckin
                
                if ($checkinResult) {
                    Write-Log "AutoPilot tagging and checkin completed successfully" -Level "INFO"
                    return 0
                } else {
                    Write-Log "AutoPilot tagging succeeded but checkin failed" -Level "WARNING"
                    return 1
                }
            } else {
                Write-Log "AutoPilot tag verification failed" -Level "ERROR"
                return 2
            }
        } else {
            Write-Log "AutoPilot tagging failed" -Level "ERROR"
            return 3
        }
        
    } catch {
        Write-Log "Unexpected error in main execution: $($_.Exception.Message)" -Level "ERROR"
        Write-Log "Stack trace: $($_.ScriptStackTrace)" -Level "DEBUG"
        return 99
    }
}

# Script entry point
$exitCode = Main
Write-Log "Script completed with exit code: $exitCode" -Level "INFO"
exit $exitCode