# Power Plan Analyzer Script
# This script exports and analyzes power plan settings in detail

param(
    [string]$ExportPath = "C:\temp\PowerPlanAnalysis",
    [string]$PowerPlanGUID = $null  # Leave empty to analyze active plan
)

# Create export directory if it doesn't exist
if (-not (Test-Path -Path $ExportPath)) {
    New-Item -Path $ExportPath -ItemType Directory -Force | Out-Null
}

Write-Host "Power Plan Analysis Tool" -ForegroundColor Green
Write-Host "======================" -ForegroundColor Green

# Function to get all power plans
function Get-PowerPlans {
    $plans = @()
    $output = powercfg /list
    
    foreach ($line in $output) {
        if ($line -match "Power Scheme GUID: ([a-fA-F0-9-]+)\s+\((.+?)\)(\s+\*)?") {
            $plans += @{
                GUID = $matches[1]
                Name = $matches[2]
                IsActive = $matches[3] -eq " *"
            }
        }
    }
    return $plans
}

# Function to get detailed power settings
function Get-PowerPlanSettings {
    param([string]$GUID)
    
    $settings = @()
    $output = powercfg /query $GUID
    
    $currentSubgroup = ""
    $currentSetting = ""
    
    foreach ($line in $output) {
        if ($line -match "Subgroup GUID: ([a-fA-F0-9-]+)\s+\((.+?)\)") {
            $currentSubgroup = $matches[2]
        }
        elseif ($line -match "Power Setting GUID: ([a-fA-F0-9-]+)\s+\((.+?)\)") {
            $currentSetting = $matches[2]
        }
        elseif ($line -match "Current AC Power Setting Index: (.+)") {
            $acValue = $matches[1]
            $settings += @{
                Subgroup = $currentSubgroup
                Setting = $currentSetting
                ACValue = $acValue
                DCValue = ""
            }
        }
        elseif ($line -match "Current DC Power Setting Index: (.+)") {
            $dcValue = $matches[1]
            if ($settings.Count -gt 0) {
                $settings[-1].DCValue = $dcValue
            }
        }
    }
    
    return $settings
}

# Function to convert time values to readable format
function Convert-TimeValue {
    param([string]$Value)
    
    # Handle empty or null values
    if ([string]::IsNullOrWhiteSpace($Value)) {
        return "Not Set"
    }
    
    # Remove any whitespace
    $Value = $Value.Trim()
    
    # Handle hex values (like 0x00000258)
    if ($Value -match "^0x[0-9a-fA-F]+$") {
        try {
            $seconds = [Convert]::ToInt32($Value, 16)
        }
        catch {
            return $Value  # Return original if conversion fails
        }
    }
    # Handle decimal values
    elseif ($Value -match "^\d+$") {
        $seconds = [int]$Value
    }
    # Handle zero values
    elseif ($Value -eq "0" -or $Value -eq "0x00000000") {
        return "Never"
    }
    else {
        # For non-numeric values (like processor states), return as-is
        return $Value
    }
    
    # Convert seconds to readable format
    if ($seconds -eq 0) {
        return "Never"
    }
    elseif ($seconds -lt 60) {
        return "$seconds seconds"
    }
    elseif ($seconds -lt 3600) {
        $minutes = [math]::Round($seconds / 60)
        return "$minutes minutes"
    }
    elseif ($seconds -lt 86400) {
        $hours = [math]::Round($seconds / 3600, 2)
        return "$hours hours"
    }
    else {
        $days = [math]::Round($seconds / 86400, 2)
        return "$days days"
    }
}

# Get all power plans
$powerPlans = Get-PowerPlans

Write-Host "`nAvailable Power Plans:" -ForegroundColor Yellow
foreach ($plan in $powerPlans) {
    $activeIndicator = if ($plan.IsActive) { " (ACTIVE)" } else { "" }
    Write-Host "- $($plan.Name) [$($plan.GUID)]$activeIndicator" -ForegroundColor Cyan
}

# Determine which plan to analyze
if ([string]::IsNullOrEmpty($PowerPlanGUID)) {
    $activePlan = $powerPlans | Where-Object { $_.IsActive }
    if ($activePlan) {
        $PowerPlanGUID = $activePlan.GUID
        $planName = $activePlan.Name
        Write-Host "`nAnalyzing active power plan: $planName" -ForegroundColor Green
    }
    else {
        Write-Host "No active power plan found!" -ForegroundColor Red
        exit 1
    }
}
else {
    $selectedPlan = $powerPlans | Where-Object { $_.GUID -eq $PowerPlanGUID }
    if ($selectedPlan) {
        $planName = $selectedPlan.Name
        Write-Host "`nAnalyzing specified power plan: $planName" -ForegroundColor Green
    }
    else {
        Write-Host "Specified power plan GUID not found!" -ForegroundColor Red
        exit 1
    }
}

# Export the power plan file
$exportFile = Join-Path $ExportPath "$($planName -replace '[^\w\s-]', '').pow"
Write-Host "`nExporting power plan to: $exportFile" -ForegroundColor Yellow

try {
    powercfg /export $exportFile $PowerPlanGUID
    Write-Host "Power plan exported successfully!" -ForegroundColor Green
}
catch {
    Write-Host "Failed to export power plan: $($_.Exception.Message)" -ForegroundColor Red
}

# Get detailed settings
Write-Host "`nAnalyzing power plan settings..." -ForegroundColor Yellow
$settings = Get-PowerPlanSettings -GUID $PowerPlanGUID

# Export detailed settings to file
$detailsFile = Join-Path $ExportPath "$($planName -replace '[^\w\s-]', '')_Details.txt"
$csvFile = Join-Path $ExportPath "$($planName -replace '[^\w\s-]', '')_Settings.csv"

# Create detailed text report
$report = @"
Power Plan Analysis Report
==========================
Plan Name: $planName
Plan GUID: $PowerPlanGUID
Export Date: $(Get-Date)

Detailed Settings:
==================

"@

# Create CSV data
$csvData = @()
$csvData += "Subgroup,Setting,AC Value,DC Value,AC Readable,DC Readable"

foreach ($setting in $settings) {
    $acReadable = Convert-TimeValue -Value $setting.ACValue
    $dcReadable = Convert-TimeValue -Value $setting.DCValue
    
    $report += "Subgroup: $($setting.Subgroup)`n"
    $report += "Setting: $($setting.Setting)`n"
    $report += "AC Power: $($setting.ACValue) ($acReadable)`n"
    $report += "DC Power: $($setting.DCValue) ($dcReadable)`n"
    $report += "-" * 50 + "`n"
    
    # Add to CSV
    $csvData += "`"$($setting.Subgroup)`",`"$($setting.Setting)`",`"$($setting.ACValue)`",`"$($setting.DCValue)`",`"$acReadable`",`"$dcReadable`""
}

# Save reports
$report | Out-File -FilePath $detailsFile -Encoding UTF8
$csvData | Out-File -FilePath $csvFile -Encoding UTF8

Write-Host "`nReports generated:" -ForegroundColor Green
Write-Host "- Power Plan File: $exportFile" -ForegroundColor Cyan
Write-Host "- Detailed Report: $detailsFile" -ForegroundColor Cyan
Write-Host "- CSV Report: $csvFile" -ForegroundColor Cyan

# Display summary of key settings
Write-Host "`nKey Power Settings Summary:" -ForegroundColor Yellow
Write-Host "===========================" -ForegroundColor Yellow

$keySettings = @(
    "Turn off the display",
    "Sleep",
    "Hibernate",
    "Processor power management",
    "Hard disk",
    "Wireless Adapter Settings",
    "USB settings"
)

foreach ($keySetting in $keySettings) {
    $matchingSettings = $settings | Where-Object { $_.Setting -like "*$keySetting*" -or $_.Subgroup -like "*$keySetting*" }
    if ($matchingSettings) {
        Write-Host "`n$($keySetting):" -ForegroundColor Green
        foreach ($match in $matchingSettings) {
            $acReadable = Convert-TimeValue -Value $match.ACValue
            $dcReadable = Convert-TimeValue -Value $match.DCValue
            Write-Host "  $($match.Setting): AC=$acReadable, DC=$dcReadable" -ForegroundColor White
        }
    }
}

Write-Host "`nAnalysis complete!" -ForegroundColor Green