# Intune Registry Remediation Script
# This script creates or updates registry keys and values to match expected configuration

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

# Function to write log entries
function Write-LogEntry {
    param(
        [string]$Message,
        [string]$Level = "Info"
    )
    $TimeStamp = Get-Date -Format "yyyy-MM-dd HH:mm:ss"
    Write-Host "[$TimeStamp] [$Level] $Message"
}

# Function to create registry key if it doesn't exist
function New-RegistryKey {
    param(
        [string]$Path
    )
    try {
        if (-not (Test-Path -Path $Path)) {
            Write-LogEntry "Creating registry key: $Path"
            New-Item -Path $Path -Force | Out-Null
            return $true
        }
        return $true
    }
    catch {
        Write-LogEntry "Failed to create registry key: $Path - Error: $($_.Exception.Message)" -Level "Error"
        return $false
    }
}

# Function to set registry value
function Set-RegistryValue {
    param(
        [string]$Path,
        [string]$Name,
        $Value,
        [string]$Type
    )
    try {
        # Map type names to PowerShell registry types
        $PropertyType = switch ($Type) {
            "DWORD" { "DWord" }
            "String" { "String" }
            "ExpandString" { "ExpandString" }
            "Binary" { "Binary" }
            "MultiString" { "MultiString" }
            default { "String" }
        }
        
        # Check if the property exists
        $CurrentValue = $null
        try {
            $CurrentValue = Get-ItemProperty -Path $Path -Name $Name -ErrorAction Stop
        }
        catch {
            # Property doesn't exist, will be created
        }
        
        if ($null -eq $CurrentValue) {
            Write-LogEntry "Creating registry value: $Path\$Name = $Value ($Type)"
            New-ItemProperty -Path $Path -Name $Name -Value $Value -PropertyType $PropertyType -Force | Out-Null
        }
        else {
            Write-LogEntry "Updating registry value: $Path\$Name = $Value ($Type)"
            Set-ItemProperty -Path $Path -Name $Name -Value $Value -Type $PropertyType -Force
        }
        
        return $true
    }
    catch {
        Write-LogEntry "Failed to set registry value: $Path\$Name - Error: $($_.Exception.Message)" -Level "Error"
        return $false
    }
}

# Function to get registry value for verification
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

# Main remediation logic
Write-LogEntry "Starting registry remediation..."

$RemediationResults = @()
$SuccessfulRemediations = 0
$FailedRemediations = 0

foreach ($Check in $RegistryChecks) {
    Write-LogEntry "Processing registry entry: $($Check.Path)\$($Check.Name)"
    
    # Create registry key if it doesn't exist
    if (-not (New-RegistryKey -Path $Check.Path)) {
        $RemediationResults += "FAILED: Could not create registry key: $($Check.Path)"
        $FailedRemediations++
        continue
    }
    
    # Get current value to check if remediation is needed
    $CurrentValue = Get-RegistryValue -Path $Check.Path -Name $Check.Name
    $IsCompliant = Compare-RegistryValue -CurrentValue $CurrentValue -ExpectedValue $Check.Value -Type $Check.Type
    
    if (-not $IsCompliant) {
        Write-LogEntry "Remediation needed for: $($Check.Path)\$($Check.Name)"
        
        # Set the registry value
        if (Set-RegistryValue -Path $Check.Path -Name $Check.Name -Value $Check.Value -Type $Check.Type) {
            # Verify the change was applied
            $VerifyValue = Get-RegistryValue -Path $Check.Path -Name $Check.Name
            $IsFixed = Compare-RegistryValue -CurrentValue $VerifyValue -ExpectedValue $Check.Value -Type $Check.Type
            
            if ($IsFixed) {
                Write-LogEntry "Successfully remediated: $($Check.Path)\$($Check.Name) = $($Check.Value)" -Level "Info"
                $RemediationResults += "SUCCESS: $($Check.Path)\$($Check.Name) set to $($Check.Value)"
                $SuccessfulRemediations++
            }
            else {
                Write-LogEntry "Remediation verification failed: $($Check.Path)\$($Check.Name)" -Level "Error"
                $RemediationResults += "FAILED: Verification failed for $($Check.Path)\$($Check.Name)"
                $FailedRemediations++
            }
        }
        else {
            $RemediationResults += "FAILED: Could not set registry value: $($Check.Path)\$($Check.Name)"
            $FailedRemediations++
        }
    }
    else {
        Write-LogEntry "No remediation needed: $($Check.Path)\$($Check.Name) is already compliant" -Level "Info"
        $RemediationResults += "SKIPPED: $($Check.Path)\$($Check.Name) already compliant"
    }
}

# Summary
Write-LogEntry "Remediation completed."
Write-LogEntry "Successful remediations: $SuccessfulRemediations"
Write-LogEntry "Failed remediations: $FailedRemediations"

foreach ($Result in $RemediationResults) {
    Write-LogEntry "  - $Result"
}

# Exit with appropriate code
if ($FailedRemediations -eq 0) {
    Write-LogEntry "All remediations completed successfully." -Level "Info"
    exit 0
}
else {
    Write-LogEntry "Some remediations failed. Check logs for details." -Level "Error"
    exit 1
}