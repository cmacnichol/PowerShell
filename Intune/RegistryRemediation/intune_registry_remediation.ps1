<#
.SYNOPSIS
    Intune Registry Remediation Script - Creates or updates registry keys and values to match expected configuration.

.DESCRIPTION
    This PowerShell script is designed for use with Microsoft Intune's proactive remediation feature.
    It systematically checks and remediates registry settings to ensure compliance with organizational policies.
    
    The script performs the following operations:
    - Creates missing registry keys and full registry paths recursively
    - Sets or updates registry values to match expected configurations
    - Validates current values against expected values with type-specific comparisons
    - Provides detailed logging with color-coded output for easy monitoring
    - Returns appropriate exit codes for Intune remediation tracking
    
    Key Features:
    - Recursive registry path creation (creates intermediate keys if missing)
    - Comprehensive error handling and validation
    - Support for multiple registry value types (DWORD, String, ExpandString, Binary, MultiString, QWORD)
    - Configuration validation before processing
    - Detailed result reporting with success/failure/skip status
    - Color-coded console output for improved readability

.PARAMETER RegistryChecks
    Not a parameter - this is a script variable containing an array of hashtables.
    Each hashtable defines a registry setting to check/remediate with the following properties:
    - Path: Full registry path (e.g., "HKLM:\SOFTWARE\Policies\Microsoft\Windows\WindowsUpdate\AU")
    - Name: Registry value name (e.g., "NoAutoUpdate")
    - Value: Expected value (e.g., 1, "RemoteSigned")
    - Type: Registry value type ("DWORD", "String", "ExpandString", "Binary", "MultiString", "QWORD")

.INPUTS
    None. This script does not accept pipeline input.

.OUTPUTS
    Console output with detailed logging information.
    Exit codes:
    - 0: All remediations completed successfully
    - 1: One or more remediations failed

.EXAMPLE
    PS C:\> .\intune_registry_remediation.ps1
    
    Executes the registry remediation script with the predefined registry checks.
    Output will show detailed logging for each registry operation.

.EXAMPLE
    # To add a new registry check, modify the $RegistryChecks array:
    $RegistryChecks += @{
        Path = "HKLM:\SOFTWARE\MyCompany\Settings"
        Name = "EnableFeature"
        Value = 1
        Type = "DWORD"
    }

.NOTES
    File Name      : intune_registry_remediation.ps1
    Author         : Christopher Macnichol
    Prerequisite   : PowerShell 5.1 or later
    Created        : 07-08-2025
    Last Modified  : 07-08-2025
    Version        : 2.0
    
    Registry Paths Supported:
    - HKLM (HKEY_LOCAL_MACHINE) - Requires administrative privileges
    - HKCU (HKEY_CURRENT_USER) - Runs in user context
    - HKU (HKEY_USERS) - Requires administrative privileges
    - HKCR (HKEY_CLASSES_ROOT) - Requires administrative privileges
    - HKCC (HKEY_CURRENT_CONFIG) - Requires administrative privileges
    
    Registry Types Supported:
    - DWORD (32-bit integer)
    - QWORD (64-bit integer)
    - String (null-terminated string)
    - ExpandString (expandable string with environment variables)
    - Binary (binary data)
    - MultiString (array of null-terminated strings)
    
    Exit Codes:
    - 0: Success - All registry settings were compliant or successfully remediated
    - 1: Failure - One or more registry settings could not be remediated
    
    Logging Levels:
    - Info: General information messages (white text)
    - Success: Successful operations (green text)
    - Warning: Non-critical issues (yellow text)
    - Error: Critical errors (red text)

.FUNCTIONALITY
    Registry Management, Compliance Remediation, System Configuration

.FORWARDHELPTARGETNAME
    Microsoft.PowerShell.Management

.FORWARDHELPCATEGORY
    Cmdlet

.LINK
    https://docs.microsoft.com/en-us/mem/intune/fundamentals/remediations
    
.LINK
    https://docs.microsoft.com/en-us/powershell/module/microsoft.powershell.management/get-itemproperty
    
.LINK
    https://docs.microsoft.com/en-us/powershell/module/microsoft.powershell.management/new-item

.COMPONENT
    Microsoft Intune Proactive Remediations

.ROLE
    System Administrator, IT Professional

.TAGS
    Intune, Registry, Remediation, Compliance, Configuration, Windows

.RELATEDLINKS
    New-Item
    Get-ItemProperty
    Set-ItemProperty
    New-ItemProperty
    Test-Path

.SECURITY
    This script requires appropriate permissions to modify registry settings:
    - HKLM modifications require administrative privileges
    - HKCU modifications run in user context
    - Always test in a controlled environment before production deployment
    - Ensure proper change management procedures are followed
    - Review all registry changes for security implications

.DISCLAIMER
    This script is provided as-is without warranty. Always test thoroughly in a 
    non-production environment before deploying to production systems. Registry 
    modifications can affect system stability and security.
#>

# Define registry keys and expected values (must match detection script)
$RegistryChecks = @(
    @{
        Path = "HKLM:\SOFTWARE\Policies\Microsoft\Windows\WindowsUpdate\AU"
        Name = "NoAutoUpdate"
        Value = 1
        Type = "DWORD"
    },
    @{
        Path = "HKLM:\SOFTWARE\Policies\Microsoft\Windows\WindowsUpdate\AU"
        Name = "AUOptions"
        Value = 4
        Type = "DWORD"
    },
    @{
        Path = "HKLM:\SOFTWARE\Microsoft\Windows\CurrentVersion\Policies\System"
        Name = "EnableLUA"
        Value = 1
        Type = "DWORD"
    },
    @{
        Path = "HKLM:\SOFTWARE\Policies\Microsoft\Windows\PowerShell\ExecutionPolicy"
        Name = "ExecutionPolicy"
        Value = "RemoteSigned"
        Type = "String"
    },
    @{
        Path = "HKCU:\SOFTWARE\Microsoft\Windows\CurrentVersion\Explorer\Advanced"
        Name = "Hidden"
        Value = 1
        Type = "DWORD"
    }
)

# Function to write log entries with improved formatting
function Write-LogEntry {
    param(
        [Parameter(Mandatory = $true)]
        [string]$Message,
        [ValidateSet("Info", "Warning", "Error", "Success")]
        [string]$Level = "Info"
    )
    
    $TimeStamp = Get-Date -Format "yyyy-MM-dd HH:mm:ss"
    $LogMessage = "[$TimeStamp] [$Level] $Message"
    
    # Color-code output based on level
    switch ($Level) {
        "Error" { Write-Host $LogMessage -ForegroundColor Red }
        "Warning" { Write-Host $LogMessage -ForegroundColor Yellow }
        "Success" { Write-Host $LogMessage -ForegroundColor Green }
        default { Write-Host $LogMessage }
    }
}

# Function to create registry key recursively (creates full path if needed)
function New-RegistryKeyRecursive {
    param(
        [Parameter(Mandatory = $true)]
        [string]$Path
    )
    
    try {
        if (Test-Path -Path $Path) {
            Write-LogEntry "Registry key already exists: $Path"
            return $true
        }
        
        # Split the path and create each level if needed
        $PathParts = $Path -split '\\'
        $CurrentPath = $PathParts[0]  # Start with root (HKLM:, HKCU:, etc.)
        
        for ($i = 1; $i -lt $PathParts.Length; $i++) {
            $CurrentPath = Join-Path -Path $CurrentPath -ChildPath $PathParts[$i]
            
            if (-not (Test-Path -Path $CurrentPath)) {
                Write-LogEntry "Creating registry key: $CurrentPath"
                New-Item -Path $CurrentPath -Force | Out-Null
            }
        }
        
        # Final verification
        if (Test-Path -Path $Path) {
            Write-LogEntry "Successfully created registry path: $Path" -Level "Success"
            return $true
        }
        else {
            Write-LogEntry "Failed to create registry path: $Path" -Level "Error"
            return $false
        }
    }
    catch {
        Write-LogEntry "Exception creating registry key: $Path - Error: $($_.Exception.Message)" -Level "Error"
        return $false
    }
}

# Function to set registry value with improved error handling
function Set-RegistryValue {
    param(
        [Parameter(Mandatory = $true)]
        [string]$Path,
        [Parameter(Mandatory = $true)]
        [string]$Name,
        [Parameter(Mandatory = $true)]
        $Value,
        [Parameter(Mandatory = $true)]
        [ValidateSet("DWORD", "String", "ExpandString", "Binary", "MultiString", "QWORD")]
        [string]$Type
    )
    
    try {
        # Map type names to PowerShell registry types
        $PropertyType = switch ($Type) {
            "DWORD" { "DWord" }
            "QWORD" { "QWord" }
            "String" { "String" }
            "ExpandString" { "ExpandString" }
            "Binary" { "Binary" }
            "MultiString" { "MultiString" }
            default { "String" }
        }
        
        # Check if the property exists
        $PropertyExists = $false
        try {
            $null = Get-ItemProperty -Path $Path -Name $Name -ErrorAction Stop
            $PropertyExists = $true
        }
        catch [System.Management.Automation.PSArgumentException] {
            # Property doesn't exist
            $PropertyExists = $false
        }
        catch {
            # Other error occurred
            throw $_
        }
        
        if ($PropertyExists) {
            Write-LogEntry "Updating existing registry value: $Path\$Name = $Value ($Type)"
            Set-ItemProperty -Path $Path -Name $Name -Value $Value -Type $PropertyType -Force
        }
        else {
            Write-LogEntry "Creating new registry value: $Path\$Name = $Value ($Type)"
            New-ItemProperty -Path $Path -Name $Name -Value $Value -PropertyType $PropertyType -Force | Out-Null
        }
        
        return $true
    }
    catch {
        Write-LogEntry "Failed to set registry value: $Path\$Name - Error: $($_.Exception.Message)" -Level "Error"
        return $false
    }
}

# Function to get registry value with improved error handling
function Get-RegistryValue {
    param(
        [Parameter(Mandatory = $true)]
        [string]$Path,
        [Parameter(Mandatory = $true)]
        [string]$Name
    )
    
    try {
        $Property = Get-ItemProperty -Path $Path -Name $Name -ErrorAction Stop
        return $Property.$Name
    }
    catch [System.Management.Automation.PSArgumentException] {
        # Property doesn't exist
        return $null
    }
    catch [System.Management.Automation.ItemNotFoundException] {
        # Registry key doesn't exist
        return $null
    }
    catch {
        Write-LogEntry "Error retrieving registry value: $Path\$Name - Error: $($_.Exception.Message)" -Level "Warning"
        return $null
    }
}

# Function to compare values based on type with improved type handling
function Compare-RegistryValue {
    param(
        $CurrentValue,
        $ExpectedValue,
        [string]$Type
    )
    
    if ($null -eq $CurrentValue) {
        return $false
    }
    
    try {
        switch ($Type) {
            "DWORD" {
                return [int]$CurrentValue -eq [int]$ExpectedValue
            }
            "QWORD" {
                return [long]$CurrentValue -eq [long]$ExpectedValue
            }
            { $_ -in @("String", "ExpandString") } {
                return [string]$CurrentValue -eq [string]$ExpectedValue
            }
            "Binary" {
                # For binary data, compare as byte arrays if possible
                if ($CurrentValue -is [byte[]] -and $ExpectedValue -is [byte[]]) {
                    return (Compare-Object $CurrentValue $ExpectedValue) -eq $null
                }
                return [string]$CurrentValue -eq [string]$ExpectedValue
            }
            "MultiString" {
                if ($CurrentValue -is [string[]] -and $ExpectedValue -is [string[]]) {
                    return (Compare-Object $CurrentValue $ExpectedValue) -eq $null
                }
                return [string]$CurrentValue -eq [string]$ExpectedValue
            }
            default {
                return [string]$CurrentValue -eq [string]$ExpectedValue
            }
        }
    }
    catch {
        Write-LogEntry "Error comparing registry values: $($_.Exception.Message)" -Level "Warning"
        return $false
    }
}

# Function to validate registry check configuration
function Test-RegistryCheckConfiguration {
    param(
        [Parameter(Mandatory = $true)]
        [array]$RegistryChecks
    )
    
    $ValidationErrors = @()
    
    foreach ($Check in $RegistryChecks) {
        if (-not $Check.Path) {
            $ValidationErrors += "Registry check missing Path property"
        }
        if (-not $Check.Name) {
            $ValidationErrors += "Registry check missing Name property for path: $($Check.Path)"
        }
        if ($null -eq $Check.Value) {
            $ValidationErrors += "Registry check missing Value property for: $($Check.Path)\$($Check.Name)"
        }
        if (-not $Check.Type) {
            $ValidationErrors += "Registry check missing Type property for: $($Check.Path)\$($Check.Name)"
        }
        elseif ($Check.Type -notin @("DWORD", "String", "ExpandString", "Binary", "MultiString", "QWORD")) {
            $ValidationErrors += "Invalid Type '$($Check.Type)' for: $($Check.Path)\$($Check.Name)"
        }
    }
    
    if ($ValidationErrors.Count -gt 0) {
        Write-LogEntry "Configuration validation failed:" -Level "Error"
        foreach ($Error in $ValidationErrors) {
            Write-LogEntry "  - $Error" -Level "Error"
        }
        return $false
    }
    
    return $true
}

# Main remediation logic
Write-LogEntry "Starting registry remediation..." -Level "Info"
Write-LogEntry "Processing $($RegistryChecks.Count) registry entries"

# Validate configuration
if (-not (Test-RegistryCheckConfiguration -RegistryChecks $RegistryChecks)) {
    Write-LogEntry "Configuration validation failed. Exiting." -Level "Error"
    exit 1
}

$RemediationResults = @()
$SuccessfulRemediations = 0
$FailedRemediations = 0
$SkippedRemediations = 0

foreach ($Check in $RegistryChecks) {
    Write-LogEntry "Processing registry entry: $($Check.Path)\$($Check.Name)"
    
    # Create registry key path if it doesn't exist
    if (-not (New-RegistryKeyRecursive -Path $Check.Path)) {
        $RemediationResults += [PSCustomObject]@{
            Status = "FAILED"
            Path = $Check.Path
            Name = $Check.Name
            Reason = "Could not create registry key path"
        }
        $FailedRemediations++
        continue
    }
    
    # Get current value to check if remediation is needed
    $CurrentValue = Get-RegistryValue -Path $Check.Path -Name $Check.Name
    $IsCompliant = Compare-RegistryValue -CurrentValue $CurrentValue -ExpectedValue $Check.Value -Type $Check.Type
    
    if (-not $IsCompliant) {
        Write-LogEntry "Remediation needed for: $($Check.Path)\$($Check.Name) (Current: $CurrentValue, Expected: $($Check.Value))"
        
        # Set the registry value
        if (Set-RegistryValue -Path $Check.Path -Name $Check.Name -Value $Check.Value -Type $Check.Type) {
            # Verify the change was applied
            Start-Sleep -Milliseconds 100  # Brief pause to ensure registry write is complete
            $VerifyValue = Get-RegistryValue -Path $Check.Path -Name $Check.Name
            $IsFixed = Compare-RegistryValue -CurrentValue $VerifyValue -ExpectedValue $Check.Value -Type $Check.Type
            
            if ($IsFixed) {
                Write-LogEntry "Successfully remediated: $($Check.Path)\$($Check.Name) = $($Check.Value)" -Level "Success"
                $RemediationResults += [PSCustomObject]@{
                    Status = "SUCCESS"
                    Path = $Check.Path
                    Name = $Check.Name
                    Reason = "Successfully set to $($Check.Value)"
                }
                $SuccessfulRemediations++
            }
            else {
                Write-LogEntry "Remediation verification failed: $($Check.Path)\$($Check.Name) (Set: $($Check.Value), Got: $VerifyValue)" -Level "Error"
                $RemediationResults += [PSCustomObject]@{
                    Status = "FAILED"
                    Path = $Check.Path
                    Name = $Check.Name
                    Reason = "Verification failed after setting value"
                }
                $FailedRemediations++
            }
        }
        else {
            $RemediationResults += [PSCustomObject]@{
                Status = "FAILED"
                Path = $Check.Path
                Name = $Check.Name
                Reason = "Could not set registry value"
            }
            $FailedRemediations++
        }
    }
    else {
        Write-LogEntry "No remediation needed: $($Check.Path)\$($Check.Name) is already compliant (Value: $CurrentValue)" -Level "Info"
        $RemediationResults += [PSCustomObject]@{
            Status = "SKIPPED"
            Path = $Check.Path
            Name = $Check.Name
            Reason = "Already compliant"
        }
        $SkippedRemediations++
    }
}

# Summary
Write-LogEntry "Remediation completed." -Level "Info"
Write-LogEntry "Successful remediations: $SuccessfulRemediations" -Level "Success"
Write-LogEntry "Failed remediations: $FailedRemediations" -Level "Error"
Write-LogEntry "Skipped remediations: $SkippedRemediations" -Level "Info"

Write-LogEntry "Detailed Results:" -Level "Info"
$RemediationResults | ForEach-Object {
    $Color = switch ($_.Status) {
        "SUCCESS" { "Success" }
        "FAILED" { "Error" }
        "SKIPPED" { "Info" }
    }
    Write-LogEntry "  [$($_.Status)] $($_.Path)\$($_.Name) - $($_.Reason)" -Level $Color
}

# Exit with appropriate code
if ($FailedRemediations -eq 0) {
    Write-LogEntry "All registry checks completed successfully." -Level "Success"
    exit 0
}
else {
    Write-LogEntry "Some remediations failed. Check logs for details." -Level "Error"
    exit 1
}