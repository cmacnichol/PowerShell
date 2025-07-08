# Intune Registry Remediation Scripts

Note: Readme Generated using AI.

A comprehensive PowerShell solution for Microsoft Intune's Proactive Remediations feature that detects and corrects registry configuration drift across managed Windows devices.

## 🎯 Purpose

These scripts work together to ensure critical registry settings remain compliant with organizational security policies and configuration standards. The solution automatically detects non-compliant registry values and remediates them without user intervention.

## 📋 Overview

This repository contains two complementary PowerShell scripts designed for Microsoft Intune's Proactive Remediations:

- **Detection Script** (`intune_registry_detection.ps1`) - Scans registry settings and reports compliance status
- **Remediation Script** (`intune_registry_remediation.ps1`) - Corrects non-compliant registry settings

## 🔧 How It Works

### Detection Phase
1. **Scan**: Checks predefined registry keys and values against expected configurations
2. **Compare**: Validates current values against organizational standards
3. **Report**: Returns exit codes to inform Intune about compliance status
   - Exit 0: All settings compliant
   - Exit 1: Non-compliant settings found (triggers remediation)

### Remediation Phase
1. **Create**: Builds missing registry paths recursively
2. **Set**: Updates registry values to match expected configurations
3. **Verify**: Confirms changes were applied successfully
4. **Report**: Provides detailed logging and exit codes for monitoring

## 🛠️ Features

### Detection Script Features
- ✅ Non-invasive registry scanning
- ✅ Type-aware value comparison
- ✅ Comprehensive error handling
- ✅ Detailed compliance reporting
- ✅ Support for all common registry types

### Remediation Script Features
- ✅ **Recursive path creation** - Creates missing intermediate registry keys
- ✅ **Multi-type support** - DWORD, String, ExpandString, Binary, MultiString, QWORD
- ✅ **Configuration validation** - Validates settings before processing
- ✅ **Color-coded logging** - Easy-to-read console output
- ✅ **Verification system** - Confirms all changes were applied
- ✅ **Comprehensive error handling** - Graceful handling of edge cases

## 📊 Supported Registry Types

| Type | Description | Example Use Case |
|------|-------------|------------------|
| `DWORD` | 32-bit integer | Feature toggles, numeric settings |
| `QWORD` | 64-bit integer | Large numeric values, timestamps |
| `String` | Text value | File paths, configuration strings |
| `ExpandString` | Expandable string | Environment variable paths |
| `Binary` | Binary data | Encrypted settings, complex data |
| `MultiString` | String array | Lists of values, multiple paths |

## 🚀 Quick Start

### 1. Configure Registry Settings
Edit the `$RegistryChecks` array in both scripts to define your organization's registry requirements:

```powershell
$RegistryChecks = @(
    @{
        Path = "HKLM:\SOFTWARE\Policies\Microsoft\Windows\WindowsUpdate\AU"
        Name = "NoAutoUpdate"
        Value = 1
        Type = "DWORD"
    },
    @{
        Path = "HKLM:\SOFTWARE\Policies\Microsoft\Windows\PowerShell\ExecutionPolicy"
        Name = "ExecutionPolicy"
        Value = "RemoteSigned"
        Type = "String"
    }
)
```

### 2. Deploy to Intune
1. Navigate to **Microsoft Endpoint Manager admin center**
2. Go to **Reports** > **Endpoint analytics** > **Proactive remediations**
3. Click **Create script package**
4. Upload the detection script and remediation script
5. Configure assignment and schedule

### 3. Monitor Results
- View compliance status in Intune reporting
- Check device-level remediation results
- Monitor script execution logs

## 📁 Repository Structure

```
├── Detection/
│   └── intune_registry_detection.ps1      # Detection script
├── Remediation/
│   └── intune_registry_remediation.ps1    # Remediation script
├── Examples/
│   ├── common_settings.ps1               # Common registry configurations
│   └── security_hardening.ps1            # Security-focused settings
├── Documentation/
│   ├── deployment_guide.md               # Step-by-step deployment
│   └── troubleshooting.md                # Common issues and solutions
└── README.md                             # This file
```

## ⚙️ Configuration Examples

### Windows Update Settings
```powershell
@{
    Path = "HKLM:\SOFTWARE\Policies\Microsoft\Windows\WindowsUpdate\AU"
    Name = "NoAutoUpdate"
    Value = 1
    Type = "DWORD"
}
```

### PowerShell Execution Policy
```powershell
@{
    Path = "HKLM:\SOFTWARE\Policies\Microsoft\Windows\PowerShell\ExecutionPolicy"
    Name = "ExecutionPolicy"
    Value = "RemoteSigned"
    Type = "String"
}
```

### User Account Control
```powershell
@{
    Path = "HKLM:\SOFTWARE\Microsoft\Windows\CurrentVersion\Policies\System"
    Name = "EnableLUA"
    Value = 1
    Type = "DWORD"
}
```

## 🔍 Monitoring and Logging

### Console Output
The scripts provide color-coded console output:
- 🟢 **Green**: Successful operations
- 🔴 **Red**: Errors and failures
- 🟡 **Yellow**: Warnings
- ⚪ **White**: Informational messages

### Exit Codes
| Code | Meaning | Action |
|------|---------|---------|
| 0 | Success/Compliant | No action needed |
| 1 | Non-compliant/Failed | Triggers remediation |

### Intune Reporting
- **Detection results**: Shows compliance status across devices
- **Remediation results**: Displays successful fixes and failures
- **Device details**: Per-device execution logs and status

## 🛡️ Security Considerations

### Permissions Required
- **HKLM modifications**: Administrative privileges required
- **HKCU modifications**: User context sufficient
- **Registry access**: Appropriate permissions for target keys

### Best Practices
- ✅ Test all configurations in a lab environment first
- ✅ Use least-privilege principles
- ✅ Implement proper change management
- ✅ Monitor for unintended consequences
- ✅ Maintain configuration documentation

### Security Recommendations
- Review all registry changes for security implications
- Ensure configurations align with security baselines
- Test impact on application functionality
- Monitor for privilege escalation risks

## 🐛 Troubleshooting

### Common Issues

**Issue**: Registry path doesn't exist
- **Solution**: The remediation script automatically creates missing paths

**Issue**: Access denied errors
- **Solution**: Ensure script runs with appropriate privileges for target registry hive

**Issue**: Value comparison fails
- **Solution**: Verify data types match between expected and actual values

**Issue**: Remediation verification fails
- **Solution**: Check for registry virtualization or redirection

### Debug Mode
Enable verbose logging by modifying the `Write-LogEntry` function calls to include more detail during troubleshooting.

## 🔄 Version History

### Version 2.0
- Added recursive registry path creation
- Improved error handling and validation
- Enhanced logging with color-coded output
- Added support for QWORD registry type
- Comprehensive configuration validation

### Version 1.0
- Initial release
- Basic detection and remediation functionality
- Support for common registry types

## 🤝 Contributing

We welcome contributions to improve these scripts! Please:

1. Fork the repository
2. Create a feature branch
3. Make your changes
4. Add appropriate tests
5. Submit a pull request

### Development Guidelines
- Follow PowerShell best practices
- Include comprehensive error handling
- Add appropriate logging
- Update documentation
- Test in multiple environments

## 📄 License

This project is licensed under the MIT License - see the [LICENSE](LICENSE) file for details.

## 🆘 Support

For issues and questions:
- **GitHub Issues**: Report bugs and feature requests
- **Documentation**: Check the `/Documentation` folder
- **Community**: Join discussions in the Issues section

## 📚 Additional Resources

- [Microsoft Intune Proactive Remediations Documentation](https://docs.microsoft.com/en-us/mem/intune/fundamentals/remediations)
- [PowerShell Registry Management](https://docs.microsoft.com/en-us/powershell/module/microsoft.powershell.management/)
- [Windows Registry Reference](https://docs.microsoft.com/en-us/windows/win32/sysinfo/registry)

---

**⚠️ Disclaimer**: These scripts are provided as-is without warranty. Always test thoroughly in a non-production environment before deploying to production systems. Registry modifications can affect system stability and security.