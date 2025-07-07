# Intune Registry Detection Script
# This script checks multiple registry keys and values
# Returns exit code 0 if compliant, exit code 1 if remediation needed

# Define registry keys and expected values
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

# Function to write log entries
function Write-LogEntry {
    param(
        [string]$Message,
        [string]$Level = "Info"
    )
    $TimeStamp = Get-Date -Format "yyyy-MM-dd HH:mm:ss"
    Write-Host "[$TimeStamp] [$Level] $Message"
}

# Function to check if registry key exists
function Test-RegistryKey {
    param(
        [string]$Path
    )
    try {
        return Test-Path -Path $Path
    }
    catch {
        return $false
    }
}

# Function to get registry value
function Get-RegistryValue {
    param(
        [string]$Path,
        [string]$Name
    )
    try {
        $value = Get-ItemProperty -Path $Path -Name $Name -ErrorAction Stop
        return $value.$Name
    }
    catch {
        return $null
    }
}

# Function to compare values based on type
function Compare-RegistryValue {
    param(
        $CurrentValue,
        $ExpectedValue,
        [string]$Type
    )
    
    if ($null -eq $CurrentValue) {
        return $false
    }
    
    switch ($Type) {
        "DWORD" {
            return [int]$CurrentValue -eq [int]$ExpectedValue
        }
        "String" {
            return [string]$CurrentValue -eq [string]$ExpectedValue
        }
        "ExpandString" {
            return [string]$CurrentValue -eq [string]$ExpectedValue
        }
        "Binary" {
            return [string]$CurrentValue -eq [string]$ExpectedValue
        }
        "MultiString" {
            return [string]$CurrentValue -eq [string]$ExpectedValue
        }
        default {
            return [string]$CurrentValue -eq [string]$ExpectedValue
        }
    }
}

# Main detection logic
Write-LogEntry "Starting registry compliance check..."

$ComplianceIssues = @()

foreach ($Check in $RegistryChecks) {
    Write-LogEntry "Checking registry path: $($Check.Path)"
    
    # Check if registry key exists
    if (-not (Test-RegistryKey -Path $Check.Path)) {
        Write-LogEntry "Registry key does not exist: $($Check.Path)" -Level "Warning"
        $ComplianceIssues += "Missing registry key: $($Check.Path)"
        continue
    }
    
    # Get current value
    $CurrentValue = Get-RegistryValue -Path $Check.Path -Name $Check.Name
    
    if ($null -eq $CurrentValue) {
        Write-LogEntry "Registry value does not exist: $($Check.Path)\$($Check.Name)" -Level "Warning"
        $ComplianceIssues += "Missing registry value: $($Check.Path)\$($Check.Name)"
        continue
    }
    
    # Compare values
    $IsCompliant = Compare-RegistryValue -CurrentValue $CurrentValue -ExpectedValue $Check.Value -Type $Check.Type
    
    if (-not $IsCompliant) {
        Write-LogEntry "Registry value mismatch: $($Check.Path)\$($Check.Name) - Current: $CurrentValue, Expected: $($Check.Value)" -Level "Warning"
        $ComplianceIssues += "Incorrect value: $($Check.Path)\$($Check.Name) (Current: $CurrentValue, Expected: $($Check.Value))"
    }
    else {
        Write-LogEntry "Registry value compliant: $($Check.Path)\$($Check.Name) = $CurrentValue" -Level "Info"
    }
}

# Determine compliance status
if ($ComplianceIssues.Count -eq 0) {
    Write-LogEntry "All registry checks passed. Device is compliant." -Level "Info"
    exit 0
}
else {
    Write-LogEntry "Found $($ComplianceIssues.Count) compliance issues:" -Level "Warning"
    foreach ($Issue in $ComplianceIssues) {
        Write-LogEntry "  - $Issue" -Level "Warning"
    }
    Write-LogEntry "Device requires remediation." -Level "Warning"
    exit 1
}