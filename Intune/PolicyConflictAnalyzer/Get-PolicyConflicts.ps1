<#
.SYNOPSIS
    Analyzes Microsoft Intune policy JSON exports to identify conflicting and duplicate settings across policies.

.DESCRIPTION
    The Intune Policy Conflict Analyzer is a PowerShell script that processes JSON exports of Microsoft Intune policies 
    to detect configuration conflicts and duplicate settings. It recursively parses nested JSON structures, compares 
    settings across policies of the same type, and generates both screen output and CSV reports.

    The script helps administrators identify:
    - Conflicting settings (same setting with different values across policies)
    - Duplicate settings (same setting with same value across multiple policies)
    - Policy consolidation opportunities
    - Configuration inconsistencies

.PARAMETER FolderPath
    Mandatory. The path to the folder containing JSON exports of Intune policies.
    All .json files in this folder will be analyzed.

.PARAMETER OutputCsvPath
    Optional. The path where the CSV report will be saved. 
    Default: ".\IntuneConflicts_YYYYMMDD_HHMMSS.csv" in the current directory.

.PARAMETER IncludeDuplicates
    Optional switch. When specified, the script will also detect and report settings that appear 
    in multiple policies with the same value (duplicates), not just conflicts.

.INPUTS
    None. The script reads JSON files from the specified folder path.

.OUTPUTS
    - Console output with detailed conflict and duplicate analysis
    - CSV file containing all detected issues with the following columns:
      * SettingName: The configuration setting path in dot notation
      * PolicyType: The type of Intune policy (e.g., compliance, configuration)
      * Value: The setting value
      * ConflictingPolicies: List of policies containing this setting
      * PolicyCount: Number of policies with this setting
      * IssueType: "Conflict" or "Duplicate"

.EXAMPLE
    .\IntuneConflictAnalyzer.ps1 -FolderPath "C:\IntuneExports"
    
    Analyzes all JSON files in C:\IntuneExports for conflicts only, saves results to default CSV location.

.EXAMPLE
    .\IntuneConflictAnalyzer.ps1 -FolderPath "C:\IntuneExports" -IncludeDuplicates
    
    Analyzes all JSON files for both conflicts and duplicates, saves results to default CSV location.

.EXAMPLE
    .\IntuneConflictAnalyzer.ps1 -FolderPath "C:\IntuneExports" -IncludeDuplicates -OutputCsvPath "C:\Reports\MyAnalysis.csv"
    
    Full analysis with custom output path for the CSV report.

.NOTES
    Author: Christopher Macnichol
    Version: 1.0
    Created: 07/08/2025
    
    Requirements:
    - PowerShell 5.1 or higher
    - Read access to the folder containing JSON exports
    - Write access to the output CSV location
    
    Supported Policy Types:
    - Device Compliance Policies
    - Device Configuration Policies
    - Application Policies
    - Device Management Policies
    - Custom policy types with @odata.type identification
    
    The script automatically:
    - Detects policy types from JSON structure
    - Flattens nested JSON objects using dot notation
    - Filters out metadata fields (IDs, timestamps, etc.)
    - Groups comparisons by policy type
    - Handles arrays and null values appropriately

.LINK
    Microsoft Graph API Documentation: https://docs.microsoft.com/en-us/graph/api/resources/intune-graph-overview
    Microsoft Intune Documentation: https://docs.microsoft.com/en-us/mem/intune/

.FUNCTIONALITY
    Policy Analysis, Conflict Detection, Configuration Management, Intune Administration
#>

# Intune Policy Conflict Analyzer
# This script analyzes JSON exports of Intune policies to identify conflicting settings

param(
    [Parameter(Mandatory=$true)]
    [string]$FolderPath,
    
    [Parameter(Mandatory=$false)]
    [string]$OutputCsvPath = ".\IntuneConflicts_$(Get-Date -Format 'yyyyMMdd_HHmmss').csv",
    
    [Parameter(Mandatory=$false)]
    [switch]$IncludeDuplicates
)

# Function to flatten nested JSON objects into dot notation
function ConvertTo-FlattenedObject {
    param(
        [Parameter(Mandatory=$true)]
        $InputObject,
        
        [Parameter(Mandatory=$false)]
        [string]$Prefix = ""
    )
    
    $result = @{}
    
    foreach ($property in $InputObject.PSObject.Properties) {
        $key = if ($Prefix) { "$Prefix.$($property.Name)" } else { $property.Name }
        
        if ($property.Value -is [PSCustomObject] -or $property.Value -is [System.Collections.Hashtable]) {
            # Recursively flatten nested objects
            $nested = ConvertTo-FlattenedObject -InputObject $property.Value -Prefix $key
            foreach ($nestedKey in $nested.Keys) {
                $result[$nestedKey] = $nested[$nestedKey]
            }
        }
        elseif ($property.Value -is [System.Array]) {
            # Handle arrays
            if ($property.Value.Count -gt 0) {
                for ($i = 0; $i -lt $property.Value.Count; $i++) {
                    $arrayKey = "$key[$i]"
                    if ($property.Value[$i] -is [PSCustomObject] -or $property.Value[$i] -is [System.Collections.Hashtable]) {
                        $nested = ConvertTo-FlattenedObject -InputObject $property.Value[$i] -Prefix $arrayKey
                        foreach ($nestedKey in $nested.Keys) {
                            $result[$nestedKey] = $nested[$nestedKey]
                        }
                    } else {
                        $result[$arrayKey] = $property.Value[$i]
                    }
                }
            } else {
                $result[$key] = @()
            }
        }
        else {
            $result[$key] = $property.Value
        }
    }
    
    return $result
}

# Function to get policy type from JSON content
function Get-PolicyType {
    param($JsonContent)
    
    if ($JsonContent.'@odata.type') {
        return $JsonContent.'@odata.type'
    }
    elseif ($JsonContent.deviceCompliancePolicy) {
        return "CompliancePolicy"
    }
    elseif ($JsonContent.deviceConfiguration) {
        return "ConfigurationPolicy"
    }
    elseif ($JsonContent.deviceManagement) {
        return "DeviceManagement"
    }
    elseif ($JsonContent.applications) {
        return "ApplicationPolicy"
    }
    else {
        return "Unknown"
    }
}

# Main execution
try {
    Write-Host "Starting Intune Policy Conflict Analysis..." -ForegroundColor Green
    Write-Host "Folder Path: $FolderPath" -ForegroundColor Yellow
    Write-Host "Output CSV: $OutputCsvPath" -ForegroundColor Yellow
    Write-Host ""

    # Get all JSON files from the specified folder
    $jsonFiles = Get-ChildItem -Path $FolderPath -Filter "*.json" -File

    if ($jsonFiles.Count -eq 0) {
        Write-Warning "No JSON files found in the specified folder: $FolderPath"
        return
    }

    Write-Host "Found $($jsonFiles.Count) JSON files to analyze" -ForegroundColor Cyan

    # Store all policy data
    $allPolicies = @()
    $allSettings = @{}

    # Process each JSON file
    foreach ($file in $jsonFiles) {
        Write-Host "Processing: $($file.Name)" -ForegroundColor Gray
        
        try {
            $jsonContent = Get-Content -Path $file.FullName -Raw | ConvertFrom-Json
            
            # Extract policy information
            $policyInfo = @{
                FileName = $file.Name
                FilePath = $file.FullName
                PolicyName = $jsonContent.displayName ?? $jsonContent.name ?? $file.BaseName
                PolicyType = Get-PolicyType -JsonContent $jsonContent
                RawContent = $jsonContent
            }
            
            # Flatten the JSON structure
            $flattenedSettings = ConvertTo-FlattenedObject -InputObject $jsonContent
            
            # Remove metadata fields that shouldn't be compared
            $metadataKeys = @(
                "id", "createdDateTime", "lastModifiedDateTime", "version", 
                "@odata.type", "@odata.context", "etag", "supportsScopeTags",
                "roleScopeTagIds", "deviceManagementApplicabilityRuleOsEdition",
                "deviceManagementApplicabilityRuleOsVersion", "deviceManagementApplicabilityRuleDeviceMode"
            )
            
            foreach ($key in $metadataKeys) {
                $flattenedSettings.Remove($key)
            }
            
            $policyInfo.Settings = $flattenedSettings
            $allPolicies += $policyInfo
            
            # Store settings for conflict detection
            foreach ($setting in $flattenedSettings.GetEnumerator()) {
                if (-not $allSettings.ContainsKey($setting.Key)) {
                    $allSettings[$setting.Key] = @()
                }
                
                $allSettings[$setting.Key] += @{
                    PolicyName = $policyInfo.PolicyName
                    PolicyType = $policyInfo.PolicyType
                    FileName = $policyInfo.FileName
                    Value = $setting.Value
                }
            }
        }
        catch {
            Write-Warning "Error processing file $($file.Name): $($_.Exception.Message)"
        }
    }

    # Detect conflicts and duplicates
    Write-Host "`nAnalyzing for conflicts..." -ForegroundColor Green
    $conflicts = @()
    $duplicates = @()

    foreach ($settingKey in $allSettings.Keys) {
        $settingInstances = $allSettings[$settingKey]
        
        # Only check settings that appear in multiple policies
        if ($settingInstances.Count -gt 1) {
            # Group by policy type first
            $typeGroups = $settingInstances | Group-Object -Property PolicyType
            
            foreach ($typeGroup in $typeGroups) {
                if ($typeGroup.Count -gt 1) {
                    # Check for different values within the same policy type
                    $valueGroups = $typeGroup.Group | Group-Object -Property { 
                        if ($_.Value -eq $null) { "NULL" }
                        elseif ($_.Value -is [array]) { ($_.Value | ConvertTo-Json -Compress) }
                        else { $_.Value.ToString() }
                    }
                    
                    if ($valueGroups.Count -gt 1) {
                        # Found a conflict!
                        foreach ($valueGroup in $valueGroups) {
                            $policies = $valueGroup.Group | ForEach-Object { "$($_.PolicyName) ($($_.FileName))" }
                            
                            $conflicts += [PSCustomObject]@{
                                SettingName = $settingKey
                                PolicyType = $typeGroup.Name
                                Value = $valueGroup.Name
                                ConflictingPolicies = ($policies -join "; ")
                                PolicyCount = $valueGroup.Count
                                IssueType = "Conflict"
                            }
                        }
                    }
                    elseif ($IncludeDuplicates -and $valueGroups.Count -eq 1) {
                        # Found duplicate settings with same value
                        $valueGroup = $valueGroups[0]
                        $policies = $valueGroup.Group | ForEach-Object { "$($_.PolicyName) ($($_.FileName))" }
                        
                        $duplicates += [PSCustomObject]@{
                            SettingName = $settingKey
                            PolicyType = $typeGroup.Name
                            Value = $valueGroup.Name
                            ConflictingPolicies = ($policies -join "; ")
                            PolicyCount = $valueGroup.Count
                            IssueType = "Duplicate"
                        }
                    }
                }
            }
        }
    }

    # Combine results for output
    $allIssues = @()
    $allIssues += $conflicts
    if ($IncludeDuplicates) {
        $allIssues += $duplicates
    }

    # Display results
    Write-Host "`n=== CONFLICT ANALYSIS RESULTS ===" -ForegroundColor Yellow
    Write-Host "Total Policies Analyzed: $($allPolicies.Count)" -ForegroundColor Cyan
    Write-Host "Total Settings Analyzed: $($allSettings.Count)" -ForegroundColor Cyan
    Write-Host "Conflicts Found: $($conflicts.Count)" -ForegroundColor Red
    if ($IncludeDuplicates) {
        Write-Host "Duplicates Found: $($duplicates.Count)" -ForegroundColor Magenta
    }
    Write-Host ""

    if ($allIssues.Count -gt 0) {
        # Display conflicts first
        if ($conflicts.Count -gt 0) {
            Write-Host "CONFLICTS DETECTED:" -ForegroundColor Red
            Write-Host "==================" -ForegroundColor Red
            
            $conflictGroups = $conflicts | Group-Object -Property SettingName
            
            foreach ($group in $conflictGroups) {
                Write-Host "`nSetting: $($group.Name)" -ForegroundColor Yellow
                Write-Host "Policy Type: $($group.Group[0].PolicyType)" -ForegroundColor Cyan
                
                foreach ($conflict in $group.Group) {
                    Write-Host "  Value: $($conflict.Value)" -ForegroundColor White
                    Write-Host "  Policies: $($conflict.ConflictingPolicies)" -ForegroundColor Gray
                }
            }
        }
        
        # Display duplicates if requested
        if ($IncludeDuplicates -and $duplicates.Count -gt 0) {
            Write-Host "`nDUPLICATE SETTINGS DETECTED:" -ForegroundColor Magenta
            Write-Host "============================" -ForegroundColor Magenta
            
            $duplicateGroups = $duplicates | Group-Object -Property SettingName
            
            foreach ($group in $duplicateGroups) {
                Write-Host "`nSetting: $($group.Name)" -ForegroundColor Yellow
                Write-Host "Policy Type: $($group.Group[0].PolicyType)" -ForegroundColor Cyan
                Write-Host "  Value: $($group.Group[0].Value)" -ForegroundColor White
                Write-Host "  Policies: $($group.Group[0].ConflictingPolicies)" -ForegroundColor Gray
            }
        }
        
        # Export to CSV
        Write-Host "`nExporting results to CSV: $OutputCsvPath" -ForegroundColor Green
        $allIssues | Export-Csv -Path $OutputCsvPath -NoTypeInformation
        
        Write-Host "`nCSV file created successfully!" -ForegroundColor Green
    } else {
        Write-Host "No conflicts detected! All policies have consistent settings." -ForegroundColor Green
        if ($IncludeDuplicates) {
            Write-Host "No duplicate settings found either." -ForegroundColor Green
        }
    }

    Write-Host "`nAnalysis complete!" -ForegroundColor Green

} catch {
    Write-Error "An error occurred during analysis: $($_.Exception.Message)"
    Write-Error $_.Exception.StackTrace
}