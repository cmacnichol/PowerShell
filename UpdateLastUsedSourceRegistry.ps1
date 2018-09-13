<#PSScriptInfo

    .VERSION
    0.1

    .GUID
    7025658f-5304-4700-bfd0-51ffbfbd7698

    .AUTHOR
    Chris Macnichol

    .COMPANYNAME 
    Huntington Bank

    .COPYRIGHT 

    .TAGS 

    .LICENSEURI 

    .PROJECTURI 

    .ICONURI 

    .EXTERNALMODULEDEPENDENCIES 

    .REQUIREDSCRIPTS 

    .EXTERNALSCRIPTDEPENDENCIES 

    .RELEASENOTES

    .NOTES
    
    Version History : 0.1 - Initial Script

    Created         : 10-24-2016
    Last updated    : 10-24-2016
#>

<# 

    .DESCRIPTION 
    Custom Script to Update LastUsedSource
#> 


[String] $BaseKey = 'HKLM:\Software\Classes\Installer\Products\4F2CCD5B4B1F5954A8E96CF0E76B8ABC\'
[String] $RegLocation = 'HKLM:\Software\Classes\Installer\Products\4F2CCD5B4B1F5954A8E96CF0E76B8ABC\SourceList\'
[String] $regValue = "n;1;$dirSupportFiles\\"

[String] $RegLocationNet = 'HKLM:\Software\Classes\Installer\Products\4F2CCD5B4B1F5954A8E96CF0E76B8ABC\SourceList\Net'
[String] $regValueNet = "$dirSupportFiles\"

if (Test-Path $BaseKey -ErrorAction SilentlyContinue) {

  Set-RegistryKey -Key $RegLocation -Name 'LastUsedSource' -Value $regValue -Type ExpandString
  Set-RegistryKey -Key $RegLocationNet -Name '1' -Value $regValueNet -Type ExpandString
<#
  New-ItemProperty -Path $RegLocation -Name 'LastUsedSource' -Value $regValue -Force -ErrorAction SilentlyContinue | Out-Null

  New-ItemProperty -Path $RegLocationNet -Name '1' -Value $regValueNet -Force -ErrorAction SilentlyContinue | Out-Null#>

}
