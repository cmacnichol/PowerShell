# Intune Policy Conflict Analyzer

A PowerShell script that analyzes Microsoft Intune policy JSON exports to identify conflicting and duplicate settings across policies.

## 🚀 Features

- **Conflict Detection**: Identifies settings with different values across policies of the same type
- **Duplicate Detection**: Finds redundant settings with identical values across multiple policies
- **Recursive JSON Parsing**: Handles nested policy structures and arrays
- **Policy Type Auto-Detection**: Automatically identifies and categorizes different Intune policy types
- **Dual Output**: Console display and CSV export for further analysis
- **Metadata Filtering**: Excludes system fields (IDs, timestamps) from comparison

## 📋 Requirements

- PowerShell 5.1 or higher
- Read access to folder containing JSON exports
- Write access for CSV output location

## 🔧 Installation

1. Download the `IntuneConflictAnalyzer.ps1` script
2. Place it in your preferred directory
3. Ensure PowerShell execution policy allows script execution:
   ```powershell
   Set-ExecutionPolicy -ExecutionPolicy RemoteSigned -Scope CurrentUser
   ```

## 📝 Usage

### Basic Syntax
```powershell
.\IntuneConflictAnalyzer.ps1 -FolderPath <path> [-OutputCsvPath <path>] [-IncludeDuplicates]
```

### Parameters

| Parameter | Type | Required | Description |
|-----------|------|----------|-------------|
| `FolderPath` | String | Yes | Path to folder containing JSON policy exports |
| `OutputCsvPath` | String | No | Custom path for CSV output (default: auto-generated) |
| `IncludeDuplicates` | Switch | No | Also detect duplicate settings with same values |

### Examples

#### 1. Basic Conflict Detection
```powershell
.\IntuneConflictAnalyzer.ps1 -FolderPath "C:\IntuneExports"
```
Analyzes all JSON files for conflicts only.

#### 2. Include Duplicate Detection
```powershell
.\IntuneConflictAnalyzer.ps1 -FolderPath "C:\IntuneExports" -IncludeDuplicates
```
Detects both conflicts and duplicates.

#### 3. Custom Output Path
```powershell
.\IntuneConflictAnalyzer.ps1 -FolderPath "C:\IntuneExports" -IncludeDuplicates -OutputCsvPath "C:\Reports\Analysis.csv"
```
Full analysis with custom CSV location.

## 📊 Output

### Console Output
- **Summary Statistics**: Total policies, settings, conflicts, and duplicates
- **Conflicts Section**: Settings with different values across policies
- **Duplicates Section**: Settings with same values across multiple policies (if `-IncludeDuplicates` is used)

### CSV Export
The CSV file contains the following columns:
- `SettingName`: Configuration setting path in dot notation
- `PolicyType`: Type of Intune policy
- `Value`: The setting value
- `ConflictingPolicies`: List of policies containing this setting
- `PolicyCount`: Number of policies with this setting
- `IssueType`: "Conflict" or "Duplicate"

## 🎯 Supported Policy Types

- Device Compliance Policies
- Device Configuration Policies
- Application Policies
- Device Management Policies
- Custom policies with `@odata.type` identification

## 🔍 How It Works

1. **JSON Parsing**: Recursively parses all JSON files in the specified folder
2. **Structure Flattening**: Converts nested JSON objects to dot notation (e.g., `settings.security.passwordRequired`)
3. **Metadata Filtering**: Removes system fields that shouldn't be compared
4. **Policy Grouping**: Groups settings by policy type for relevant comparisons
5. **Conflict Detection**: Identifies settings with different values
6. **Duplicate Detection**: Finds settings with identical values across policies (optional)
7. **Report Generation**: Creates console output and CSV export

## 📁 Getting JSON Exports

You can obtain Intune policy JSON exports through:

### Microsoft Graph API
```powershell
# Example using Microsoft Graph PowerShell
Connect-MgGraph -Scopes "DeviceManagementConfiguration.Read.All"
Get-MgDeviceManagementDeviceConfiguration | ConvertTo-Json -Depth 10 | Out-File "policy.json"
```

### Third-Party Tools
- IntuneBackupAndRestore PowerShell module
- Intune policy backup utilities
- Custom Graph API scripts

## 🛠️ Troubleshooting

### Common Issues

#### No JSON Files Found
```
WARNING: No JSON files found in the specified folder
```
**Solution**: Verify the folder path and ensure it contains `.json` files.

#### Permission Errors
```
ERROR: Access to the path is denied
```
**Solution**: Ensure you have read access to the input folder and write access to the output location.

#### Invalid JSON Format
```
WARNING: Error processing file: Invalid JSON format
```
**Solution**: Verify the JSON files are valid Intune policy exports.

## 🤝 Contributing

1. Fork the repository
2. Create a feature branch
3. Make your changes
4. Test thoroughly
5. Submit a pull request

## 📄 License

This project is licensed under the MIT License - see the [LICENSE](LICENSE) file for details.

## ⚠️ Disclaimer

This tool is provided as-is for educational and administrative purposes. Always test in a non-production environment first. The authors are not responsible for any changes or issues that may arise from using this script.

## 🙋 Support

For questions, issues, or feature requests:
- Open an issue in this repository
- Review the PowerShell help documentation: `Get-Help .\IntuneConflictAnalyzer.ps1 -Full`

## 📚 Related Resources

- [Microsoft Intune Documentation](https://docs.microsoft.com/en-us/mem/intune/)
- [Microsoft Graph API - Intune](https://docs.microsoft.com/en-us/graph/api/resources/intune-graph-overview)
- [PowerShell Documentation](https://docs.microsoft.com/en-us/powershell/)

---

*This README was generated with assistance from AI to ensure comprehensive documentation and best practices.*