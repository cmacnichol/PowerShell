<#
.SYNOPSIS

    Take User Names entered and adds them to the specified group.

.DESCRIPTION

    Requires
     - Powershell V2

.EXAMPLE


.NOTES

    V1.0  Chris Macnichol (04/04/2016) Intial versioning
#>
[Cmdletbinding()]
Param(
    [Parameter(ValueFromPipeline=$True, ValueFromPipelineByPropertyName=$True)]
    [array[]] $argComp = $null,
    [array[]] $User = $null,
    [switch] $gui = $false,
    [array[]]$computerName = $null,
    [string] $computerFile = "\Computers.txt",
    [string] $userFile = "\Users.txt"
    #[string] $Group = "Remote Desktop Users"
)

$ScriptName = $MyInvocation.MyCommand.path
$Directory = Split-Path $ScriptName

#$ArgList = @()
#$ArgList += @("`"$Directory\SilentOpenPS.vbs`"")
#$ArgList += @("`"$Directory\Cleanup and Check for Updates.ps1`"")
#Start-Process wscript.exe -ArgumentList $ArgList

Function Import-Computers {
#Import Computer file
if ((Test-Path $Directory$computerFile) -eq $true){
Write-Verbose "Importing Computer(s) from Computer File"
try {Get-Content -ErrorAction Stop $Directory$computerFile}
catch{}
    } #End If Test Path
    else {Write-Host "Computer name\file was not specified or does not exist.  Exiting." -ForegroundColor Red;Exit}
}

Function Import-Users {
#Import Server file
Write-Verbose "Importing User(s) from User File"
try {Get-Content -ErrorAction Stop $Directory$userFile}
catch [System.Management.Automation.ItemNotFoundException] {if($computerName -eq $null) {Write-Host "User file was not specified or not found.  Exiting" -ForegroundColor Red;Exit}else{Write-Host "Computer was specified without a user, showing report only." -ForegroundColor Red}}
catch{}
}

Function Check-Existing($user){
#Check existing users against input
#foreach ($u in $User){if(){}}
}


Function Add-Users {
#Add users to remote groups.

}

Function Remove-Users{}
Function Export-Users{}

if ($computerName -eq $null){[array]$computerName = Import-Computers}
if ($user -eq $null) {$user = Import-Users}

$groupResults = Get-Localgroup($computerName,[string]$group)

$groupResults