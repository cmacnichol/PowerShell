<#
.SYNOPSIS
    Creates a scheduled task that runs a specified PowerShell script after a user logs off (Security Event ID 4647).

.DESCRIPTION
    This script automates the creation of a Windows Scheduled Task, triggered by Security Event ID 4647 (user logoff).
    The task will execute a custom PowerShell script as SYSTEM with elevated privileges. 
    Useful for post-Autopilot ESP actions or any scenario requiring automation after user logoff.

.PARAMETER TaskName
    The name of the scheduled task to create. Default: 'PostESP-Script'.

.PARAMETER ScriptPath
    The full path to the PowerShell script to execute when the event is triggered.
    Default: 'C:\Windows\Logs\Scripts\PostESP-Action.ps1'.

.EXAMPLE
    .\Create-PostESPScheduledTask.ps1
    Creates the scheduled task with default task name and script path.

.EXAMPLE
    .\Create-PostESPScheduledTask.ps1 -TaskName "MyCustomTask" -ScriptPath "C:\Scripts\DoSomething.ps1"
    Creates the scheduled task with custom name and script path.

.NOTES
    Author: Christopher Macnichol
    Created: 2025-07-12
    Tested on: Windows 10/11, Windows Server 2019/2022
    Requires: PowerShell 5.1+, Administrator privileges

#>

param (
    [string]$TaskName = "PostESP-Script",
    [string]$ScriptPath = "C:\Windows\Logs\Scripts\PostESP-Action.ps1"
)

# Validate script path
if (-not (Test-Path $ScriptPath)) {
    Write-Error "Script path '$ScriptPath' does not exist. Exiting."
    exit 1
}

# Define the event trigger XML subscription for Security Event ID 4647
$eventQuery = @"
<QueryList>
  <Query Id="0" Path="Security">
    <Select Path="Security">*[System[EventID=4647]]</Select>
  </Query>
</QueryList>
"@

# Get the CIM class for the event trigger
$CIMTriggerClass = Get-CimClass -ClassName MSFT_TaskEventTrigger -Namespace Root/Microsoft/Windows/TaskScheduler

# Create a new CIM instance for the event trigger
$eventTrigger = New-CimInstance -CimClass $CIMTriggerClass -ClientOnly
$eventTrigger.Subscription = $eventQuery
$eventTrigger.Enabled = $true

# Create the scheduled task action to run the PowerShell script
$action = New-ScheduledTaskAction -Execute "powershell.exe" -Argument "-NoProfile -WindowStyle Hidden -ExecutionPolicy Bypass -File `"$ScriptPath`""

# Create the principal to run as SYSTEM with highest privileges
$principal = New-ScheduledTaskPrincipal -UserId "SYSTEM" -LogonType ServiceAccount -RunLevel Highest

# Create the scheduled task settings
$settings = New-ScheduledTaskSettingsSet -AllowStartIfOnBatteries -DontStopIfGoingOnBatteries -StartWhenAvailable

# Remove existing task if it exists (idempotency)
if (Get-ScheduledTask -TaskName $TaskName -ErrorAction SilentlyContinue) {
    try {
        Unregister-ScheduledTask -TaskName $TaskName -Confirm:$false -ErrorAction Stop
        Write-Host "Existing task '$TaskName' removed."
    } catch {
        Write-Error "Failed to remove existing task: $_"
        exit 1
    }
}

# Register the scheduled task
try {
    Register-ScheduledTask -TaskName $TaskName -Action $action -Trigger $eventTrigger -Principal $principal -Settings $settings -Description "Run post-ESP script after Autopilot ESP completes"
    Write-Host "Scheduled task '$TaskName' registered successfully."
} catch {
    Write-Error "Failed to register scheduled task: $_"
    exit 1
}
