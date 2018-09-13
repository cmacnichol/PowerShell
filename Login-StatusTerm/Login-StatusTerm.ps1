<# 
.SYNOPSIS 
    
.DESCRIPTION 
    
.NOTES 
    Author     : Chris Macnichol
    Version    : 0.1
                
    Changelog  : Initial Script Creation

    Script Requirements: Powershell 2.0+
                         
.EXAMPLE

.INPUTS
    Text (.txt) Server List within the same directory as the script.  
    -ServerFile to specify a Text (.txt) file.
    -Server to specify a single server to run against.

.Outputs

#> 
[CmdLetBinding()]
param (
    [string] $Server = $null,
    [string] $ServerFile = ((split-path -parent $MyInvocation.MyCommand.Path) + "\Servers.txt"),
    #[string] $ServerFile = ("U:\Documents\Scripts\vmLogin-StatusTerm\Servers.txt"),
    [switch] $Transcript
)

#Clearing Error log for Multiple Runs
$error.clear()
#Declaring Variables
$date = get-date
$dateLog = get-date -uformat '%m-%d-%Y-%H%M'
#Defines the current directory#PS2.0 Method#
$ScriptDir = Split-Path $MyInvocation.MyCommand.Path -Parent
#Script Name
$ScriptName = $MyInvocation.MyCommand.Name
# Defines the Log File Name
$Logfile = $ScriptDir + "\login-StatusTerm_log.csv"
$servers = $null

if ($Transcript -eq $true) {start-transcript -path ($PSScriptDir + "\DebugTranscript.txt") -noclobber;Write-Host "Debug Enabled, Transcript Running" -ForegroundColor Red}

function Test-IsISE {
# Checks to see if the script is running in the ISE
# try...catch accounts for:
# Set-StrictMode -Version latest
    try {    
        return $psISE -ne $null;
    }
    catch {
        return $false;
    }
}

function LogIt
{
    ## Logging Function, used for logging purposes

    param ($Process,$Type,$object,$Description)

    $Header = "Process,Type,Object,Description"
    $LogItem = "$($Process),$($Type),$($object),$($Description),$($datelog)"

    Write-Verbose $LogItem | Select Process,Type,object,Description,datefile

    if ((Test-Path "$($Logfile)") -ne $true)
    {
        Add-Content -Value $Header -Path $Logfile
        Add-Content -Value $LogItem -Path $Logfile
    }
    else
    { Add-Content -Value $LogItem -Path $Logfile }
}

Function Terminate-Logon
{
Param(
[string] $server
)
Write-Verbose "Starting Terminate Logon Function"

$fullName = "Terminating User Sessions for Server: " + $server
Write-Host $fullName -ForegroundColor DarkYellow

try {(gwmi win32_operatingsystem -ComputerName $server -ErrorAction Stop).Win32Shutdown(4) | Out-Null}
catch [System.Management.ManagementException] {Write-Host "No Logon Session to Terminate." -ForegroundColor Green}
catch {Write-Host "Failed to Terminate Server, Error Logged" -ForegroundColor Red;LogIt -Process "Terminating Session" -Type "Error" -object "$($error[0].exception)" -Description "Unknown Error"}

}

if (!($Server -eq "")){
Write-Host "Terminating Single Server"
Terminate-Logon($server)
}
else{
Write-Host "Single Server not Selected, Looking for Server File"

try
{
$servers = (Get-Content $ServerFile -ErrorAction Stop -ErrorVariable $getConError)
Write-Verbose "Server File Found."

foreach ($server in $Servers){Write-Host "Processing: ";Write-Host $Server;Terminate-Logon($server)}

}
catch{
#Write-Verbose $getConError 
Write-Host "No Server file found, Prompting for Input." -ForegroundColor Red}

if ($(Test-IsIse) -eq $false) {
[System.Reflection.Assembly]::LoadWithPartialName('Microsoft.VisualBasic') | Out-Null
$server = [Microsoft.VisualBasic.Interaction]::InputBox("Enter a Server to Terminate it's user sessions", "Terminate User Sessions") 

}
Else {
$server = Read-Host -Prompt 'Enter a Server Name to terminate user sessions'
}

if ($server -ne '') {
Terminate-Logon($server)
if ($(Test-IsIse) -eq $false) {[Microsoft.VisualBasic.Interaction]::MsgBox("Sessions Terminated")}

}
else {Write-Host "No Server has been Specified, Exiting." -ForegroundColor Red}

}


if ($Transcript -eq $true) {Stop-transcript}
