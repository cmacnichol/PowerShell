<#
.SYNOPSIS
    Post-ESP Automation Script for Windows Autopilot/Intune Deployments

.DESCRIPTION
    This script performs post-Enrollment Status Page (ESP) actions during Windows Autopilot or Intune device provisioning.
    It waits for the ESP process to complete, sets a registry tag, restarts the Tanium Client service, creates a marker file,
    and then removes its own scheduled task to prevent reruns. All actions are logged for auditing and troubleshooting.

.PARAMETER LogDir
    The directory where log files will be stored. Default: C:\Windows\Logs\Scripts

.PARAMETER MarkerFile
    The path for the marker file that signals post-ESP actions are complete. Default: C:\Windows\System32\Tasks\ESP-TaskComplete

.PARAMETER ServiceName
    The name of the service to restart after ESP. Default: Tanium Client

.PARAMETER RegPath
    The registry path where the tag will be set. Default: HKLM:\SOFTWARE\WOW6432Node\Tanium\Tanium Client\Sensor Data\Tags

.PARAMETER TagName
    The name of the registry tag to set. Default: Autopilot

.PARAMETER Proc
    The process name to monitor for ESP completion. Default: appidpolicyconverter (Windows 11)

.PARAMETER TaskName
    The name of the scheduled task to remove after completion. Default: PostESP-Script

.PARAMETER MaxWaitSeconds
    Maximum seconds to wait for the ESP process to start. Default: 600

.EXAMPLE
    .\PostESP-Script.ps1

    Runs the script with default parameters.

.EXAMPLE
    .\PostESP-Script.ps1 -Proc "wwahost" -MaxWaitSeconds 900

    Runs the script, monitoring "wwahost" (for Windows 10) and increases the wait timeout.

.NOTES
    Author: Christopher Macnichol
    Date: 2025-07-12
    Tested on: Windows 10/11, PowerShell 5.1+
    Requirements: Run as SYSTEM or with administrative privileges.
    Logging: All actions are logged to the specified log directory.
#>

param (
    [string]$LogDir = "C:\Windows\Logs\Scripts",
    [string]$MarkerFile = "C:\Windows\System32\Tasks\ESP-TaskComplete",
    [string]$ServiceName = "Tanium Client",
    [string]$RegPath = "HKLM:\SOFTWARE\WOW6432Node\Tanium\Tanium Client\Sensor Data\Tags",
    [string]$TagName = "Autopilot",
    [string]$Proc = "appidpolicyconverter", # For Windows 11
    [string]$TaskName = "PostESP-Script",
    [int]$MaxWaitSeconds = 600
)

$logFile = Join-Path $LogDir "PostESP-Task.log"

try {
    # Ensure log directory exists
    if (-not (Test-Path $LogDir)) {
        New-Item -Path $LogDir -ItemType Directory -Force | Out-Null
    }

    # Start logging
    Start-Transcript -Path $logFile -Append

    Write-Output "Post-ESP script started. Waiting for ESP process to complete..."

    # Wait for the ESP process to start and finish, with timeout
    $elapsed = 0
    $waitInterval = 0.15
    while ($elapsed -lt $MaxWaitSeconds) {
        $getprocess = Get-Process $Proc -ErrorAction SilentlyContinue
        if ($getprocess) {
            Write-Output "$Proc has started. Waiting for it to exit..."
            Wait-Process -Name $Proc
            break
        }
        Start-Sleep -Milliseconds 150
        $elapsed += $waitInterval
    }
    if ($elapsed -ge $MaxWaitSeconds) {
        Write-Output "Timeout: $Proc did not start within $MaxWaitSeconds seconds."
        exit 1
    }

    Write-Output "$Proc has ended. Performing post-ESP actions..."

    # Custom actions: Set registry tag and restart Tanium Client
    try {
        if (-not (Test-Path $RegPath)) {
            New-Item -Path $RegPath -Force | Out-Null
            Write-Output "Created registry path: $RegPath"
        }
        if (-not (Get-ItemProperty -Path $RegPath -Name $TagName -ErrorAction SilentlyContinue)) {
            New-ItemProperty -Path $RegPath -Name $TagName -Value '' -PropertyType String -Force | Out-Null
            Write-Output "Set registry tag '$TagName' with blank value."
        } else {
            Write-Output "Registry tag '$TagName' already exists."
        }

        Restart-Service -Name $ServiceName -Force
        Write-Output "Restarted service '$ServiceName'."
    } catch {
        Write-Output "Error during post-ESP actions: $_"
    }

    # Create marker file for detection
    try {
        New-Item -Path $MarkerFile -ItemType File -Force | Out-Null
        Write-Output "Created marker file: $MarkerFile"
    } catch {
        Write-Output "Failed to create marker file: $_"
    }

    # Remove the scheduled task to prevent reruns
    try {
        $task = Get-ScheduledTask -TaskName $TaskName -ErrorAction SilentlyContinue
        if ($task) {
            Unregister-ScheduledTask -TaskName $TaskName -Confirm:$false -ErrorAction Stop
            Write-Output "Removed scheduled task: $TaskName"
        } else {
            Write-Output "Scheduled task '$TaskName' not found."
        }
    } catch {
        Write-Output "Failed to remove scheduled task: $_"
    }

    Start-Sleep -Seconds 5
}
finally {
    Stop-Transcript
}

exit 0