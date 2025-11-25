<#
.SYNOPSIS
    Synchronizes user group memberships based on device group memberships using Microsoft Graph API.

.DESCRIPTION
    This script synchronizes user group memberships by identifying users associated with devices in 
    specified source device groups and adding/removing them from destination user groups. It uses 
    Microsoft Graph API batch operations for efficient processing.

    Key Features:
    - Batch operations for improved performance (up to 20 operations per API call)
    - Primary user fallback to enrolled user if primary user is not set
    - Configurable email notifications (None, Summary, or ErrorsOnly)
    - Azure Automation compatible (logs to output stream)
    - Comprehensive error handling and logging

.PARAMETER EmailMode
    Specifies when to send email notifications.
    Valid values: "None", "Summary", "ErrorsOnly"
    Default: "ErrorsOnly"
    
    - None: No email sent
    - Summary: Always send summary email after execution
    - ErrorsOnly: Send email only when errors occur

.PARAMETER RecipientEmail
    Email address to receive notifications.
    Default: "admin@yourdomain.com"

.EXAMPLE
    .\Sync-DeviceUserToGroup.ps1
    
    Runs the script with default settings (ErrorsOnly email mode).

.EXAMPLE
    .\Sync-DeviceUserToGroup.ps1 -EmailMode Summary -RecipientEmail "it-team@contoso.com"
    
    Runs the script and always sends a summary email to it-team@contoso.com.

.EXAMPLE
    .\Sync-DeviceUserToGroup.ps1 -EmailMode None
    
    Runs the script without sending any email notifications.

.NOTES
    File Name      : Sync-DeviceUserToGroup.ps1
    Author         : Christopher Macnichol
    Prerequisite   : PowerShell 7.0+, Microsoft.Graph PowerShell SDK
    Created        : 2025.11.25
    Version        : 25.11.25
    Change         : 25.11.25 - Christopher Macnichol - Initial version, Untested with Live Data
    
    REQUIRED PERMISSIONS:
    ====================
    
    Microsoft Graph API Permissions (Application or Delegated):
    
    1. Group.ReadWrite.All
       - Required to read source device groups
       - Required to add/remove members from destination user groups
    
    2. Device.Read.All
       - Required to read device information
       - Required to retrieve registered owners and users of devices
    
    3. User.Read.All
       - Required to read user information
       - Required to validate user memberships
    
    4. Mail.Send
       - Required to send email notifications via Microsoft Graph
       - Only needed if EmailMode is set to "Summary" or "ErrorsOnly"
    
    AZURE AD APP REGISTRATION SETUP:
    =================================
    
    For Azure Automation (Managed Identity):
    ----------------------------------------
    1. Enable System-assigned Managed Identity on your Automation Account
    2. In Azure AD, grant the Managed Identity the following API permissions:
       - Microsoft Graph > Group.ReadWrite.All (Application)
       - Microsoft Graph > Device.Read.All (Application)
       - Microsoft Graph > User.Read.All (Application)
       - Microsoft Graph > Mail.Send (Application)
    3. Grant admin consent for these permissions
    
    For Interactive/Service Principal:
    ----------------------------------
    1. Register an Azure AD Application
    2. Create a client secret or certificate
    3. Grant API permissions as listed above
    4. Grant admin consent
    5. Use Connect-MgGraph with appropriate authentication method
    
    CONFIGURATION:
    ==============
    
    Before running, update the $GroupMappings array with your actual group IDs:
    
    $GroupMappings = @(
        @{ SourceDeviceGroupId = "12345678-1234-1234-1234-123456789012"; 
           DestinationUserGroupId = "87654321-4321-4321-4321-210987654321" },
        @{ SourceDeviceGroupId = "abcdef12-3456-7890-abcd-ef1234567890"; 
           DestinationUserGroupId = "fedcba98-7654-3210-fedc-ba9876543210" }
    )
    
    To find Group IDs:
    - Azure Portal: Azure AD > Groups > [Group Name] > Overview > Object ID
    - PowerShell: Get-MgGroup -Filter "displayName eq 'GroupName'" | Select-Object Id
    
    AZURE AUTOMATION SETUP:
    =======================
    
    1. Create Automation Account (if not exists)
    2. Import Microsoft.Graph modules:
       - Microsoft.Graph.Authentication
       - Microsoft.Graph.Groups
       - Microsoft.Graph.Devices
       - Microsoft.Graph.Users
       - Microsoft.Graph.Users.Actions
    
    3. Create Runbook:
       - Type: PowerShell
       - Runtime version: 7.2
       - Import this script
    
    4. Configure Managed Identity permissions (see above)
    
    5. Create Schedule (optional):
       - Frequency: Daily/Weekly as needed
       - Time: Off-peak hours recommended
    
    6. Link Schedule to Runbook with parameters:
       New-AzAutomationSchedule -AutomationAccountName "MyAccount" `
           -Name "DailySync" -StartTime "02:00 AM" -DayInterval 1
    
    AUTHENTICATION IN AZURE AUTOMATION:
    ===================================
    
    Replace the Connect-MgGraph line with:
    
    try {
        Connect-MgGraph -Identity -ErrorAction Stop
        Write-Log "Successfully connected to Microsoft Graph using Managed Identity"
    } catch {
        Write-Error "Failed to connect to Microsoft Graph: $_"
        exit 1
    }
    
    MONITORING:
    ===========
    
    - Check Azure Automation job history for execution logs
    - Review email notifications for summaries and errors
    - Use Azure Monitor/Log Analytics for advanced monitoring
    - Set up alerts for failed jobs
    
    TROUBLESHOOTING:
    ================
    
    Common Issues:
    
    1. "Insufficient privileges" error
       - Verify API permissions are granted and admin consent is provided
       - Check Managed Identity has correct permissions
    
    2. "Group not found" error
       - Verify group IDs are correct (remove < > placeholders)
       - Ensure groups exist in Azure AD
    
    3. Email not sending
       - Verify Mail.Send permission is granted
       - Check RecipientEmail is valid
       - For Managed Identity, ensure it has a mailbox or use service account
    
    4. Batch operation failures
       - Check individual request errors in logs
       - Verify users exist and are not already members
    
.LINK
    https://learn.microsoft.com/en-us/graph/api/overview
    https://learn.microsoft.com/en-us/powershell/microsoftgraph/
    https://learn.microsoft.com/en-us/azure/automation/

#>

param(
    [ValidateSet("None","Summary","ErrorsOnly")]
    [string]$EmailMode = "ErrorsOnly",
    [string]$RecipientEmail = "admin@yourdomain.com"
)

# Initialize log collection for Azure Automation
$script:LogEntries = [System.Collections.ArrayList]::new()

Function Write-Log {
    param([string]$Message)
    $timestamp = (Get-Date).ToString("yyyy-MM-dd HH:mm:ss")
    $logEntry = "$timestamp - $Message"
    
    # Write to host for Azure Automation logs
    Write-Output $logEntry
    
    # Store in memory for email summary
    $null = $script:LogEntries.Add($logEntry)
}

try {
    # For Azure Automation with Managed Identity, use:
    # Connect-MgGraph -Identity -ErrorAction Stop
    
    # For interactive/development use:
    Connect-MgGraph -Scopes "Group.ReadWrite.All","Device.Read.All","User.Read.All","Mail.Send" -ErrorAction Stop
    Write-Log "Successfully connected to Microsoft Graph"
} catch {
    Write-Error "Failed to connect to Microsoft Graph: $_"
    exit 1
}

Function Send-Email {
    param([string]$Subject,[string]$Body)
    try {
        $emailParams = @{
            Message = @{
                Subject = $Subject
                Body = @{ ContentType = "Text"; Content = $Body }
                ToRecipients = @(@{ EmailAddress = @{ Address = $RecipientEmail } })
            }
            SaveToSentItems = $true
        }
        # For Managed Identity, specify a service account email instead of "me"
        Send-MgUserMail -UserId "me" -BodyParameter $emailParams
        Write-Log "Email sent: $Subject"
    } catch {
        Write-Log "ERROR: Failed to send email. $_"
    }
}

Function Invoke-GraphBatchRequest {
    param(
        [Parameter(Mandatory)]
        [array]$Requests,
        [int]$BatchSize = 20
    )
    
    $results = @()
    $batches = [Math]::Ceiling($Requests.Count / $BatchSize)
    
    for ($i = 0; $i -lt $batches; $i++) {
        $start = $i * $BatchSize
        $end = [Math]::Min(($i + 1) * $BatchSize, $Requests.Count) - 1
        $batchRequests = $Requests[$start..$end]
        
        $batchBody = @{
            requests = $batchRequests
        }
        
        try {
            $response = Invoke-MgGraphRequest -Method POST -Uri 'https://graph.microsoft.com/v1.0/$batch' -Body ($batchBody | ConvertTo-Json -Depth 10)
            $results += $response.responses
            
            # Respect rate limits
            Start-Sleep -Milliseconds 100
        } catch {
            Write-Log "ERROR: Batch request failed. $_"
            throw
        }
    }
    
    return $results
}

Function Add-UsersToGroupBatch {
    param(
        [string]$GroupId,
        [array]$UserIds
    )
    
    if ($UserIds.Count -eq 0) { return 0 }
    
    $requests = @()
    $requestId = 1
    
    foreach ($userId in $UserIds) {
        $requests += @{
            id = "$requestId"
            method = "POST"
            url = "/groups/$GroupId/members/`$ref"
            body = @{
                "@odata.id" = "https://graph.microsoft.com/v1.0/directoryObjects/$userId"
            }
            headers = @{
                "Content-Type" = "application/json"
            }
        }
        $requestId++
    }
    
    try {
        $responses = Invoke-GraphBatchRequest -Requests $requests
        $successCount = ($responses | Where-Object { $_.status -eq 204 -or $_.status -eq 201 }).Count
        $failedCount = $responses.Count - $successCount
        
        if ($failedCount -gt 0) {
            $failures = $responses | Where-Object { $_.status -ne 204 -and $_.status -ne 201 }
            foreach ($failure in $failures) {
                Write-Log "ERROR: Failed to add user (Request ID: $($failure.id)). Status: $($failure.status)"
            }
        }
        
        return $successCount
    } catch {
        Write-Log "ERROR: Batch add operation failed. $_"
        return 0
    }
}

Function Remove-UsersFromGroupBatch {
    param(
        [string]$GroupId,
        [array]$UserIds
    )
    
    if ($UserIds.Count -eq 0) { return 0 }
    
    $requests = @()
    $requestId = 1
    
    foreach ($userId in $UserIds) {
        $requests += @{
            id = "$requestId"
            method = "DELETE"
            url = "/groups/$GroupId/members/$userId/`$ref"
            headers = @{
                "Content-Type" = "application/json"
            }
        }
        $requestId++
    }
    
    try {
        $responses = Invoke-GraphBatchRequest -Requests $requests
        $successCount = ($responses | Where-Object { $_.status -eq 204 }).Count
        $failedCount = $responses.Count - $successCount
        
        if ($failedCount -gt 0) {
            $failures = $responses | Where-Object { $_.status -ne 204 }
            foreach ($failure in $failures) {
                Write-Log "ERROR: Failed to remove user (Request ID: $($failure.id)). Status: $($failure.status)"
            }
        }
        
        return $successCount
    } catch {
        Write-Log "ERROR: Batch remove operation failed. $_"
        return 0
    }
}

# ============================================================================
# CONFIGURATION: Update these group mappings with your actual Azure AD group IDs
# ============================================================================
# To find Group IDs:
# - Azure Portal: Azure AD > Groups > [Group Name] > Overview > Object ID
# - PowerShell: Get-MgGroup -Filter "displayName eq 'GroupName'" | Select-Object Id, DisplayName
# ============================================================================

$GroupMappings = @(
    @{ SourceDeviceGroupId = "<DeviceGroupID-Dev>"; DestinationUserGroupId = "<UserGroupID-Dev>" },
    @{ SourceDeviceGroupId = "<DeviceGroupID-Pilot>"; DestinationUserGroupId = "<UserGroupID-Pilot>" },
    @{ SourceDeviceGroupId = "<DeviceGroupID-Proda>"; DestinationUserGroupId = "<UserGroupID-Proda>" }
)

$ErrorSummary = @()
$UsersAdded = 0
$UsersRemoved = 0
$DevicesProcessed = 0

Write-Log "=== Starting Device User to Group Synchronization ==="

foreach ($mapping in $GroupMappings) {
    $sourceGroupId = $mapping.SourceDeviceGroupId
    $destGroupId   = $mapping.DestinationUserGroupId

    if ($sourceGroupId -like "<*>" -or $destGroupId -like "<*>") {
        $msg = "Invalid placeholder group ID detected. Please configure actual group IDs."
        Write-Log "ERROR: $msg"
        $ErrorSummary += $msg
        continue
    }

    Write-Log "Processing Source Device Group: $sourceGroupId -> Destination User Group: $destGroupId"

    try {
        $devices = Get-MgGroupMember -GroupId $sourceGroupId -All | Where-Object { $_.'@odata.type' -eq '#microsoft.graph.device' }
        $DevicesProcessed += $devices.Count
        Write-Log "Found $($devices.Count) devices in source group"
    } catch {
        $msg = "Failed to retrieve devices for group $sourceGroupId. $_"
        Write-Log "ERROR: $msg"
        $ErrorSummary += $msg
        continue
    }

    $usersToAdd = @()

    foreach ($device in $devices) {
        $deviceId = $device.Id
        try {
            $registeredOwners = Get-MgDeviceRegisteredOwner -DeviceId $deviceId
            if ($registeredOwners -and $registeredOwners.Count -gt 0) {
                # Get the actual user ID from the AdditionalProperties
                $primaryUser = $registeredOwners[0].Id
                $usersToAdd += $primaryUser
            } else {
                # Fallback: get registered users instead
                $registeredUsers = Get-MgDeviceRegisteredUser -DeviceId $deviceId
                if ($registeredUsers -and $registeredUsers.Count -gt 0) {
                    $usersToAdd += $registeredUsers[0].Id
                } else {
                    Write-Log "WARNING: No registered owner or user found for device $deviceId"
                }
            }
        } catch {
            $msg = "Failed to retrieve user for device $deviceId. $_"
            Write-Log "ERROR: $msg"
            $ErrorSummary += $msg
        }
    }

    $usersToAdd = $usersToAdd | Sort-Object -Unique
    Write-Log "Identified $($usersToAdd.Count) unique users from devices"

    try {
        $currentMembers = Get-MgGroupMember -GroupId $destGroupId -All | 
            Where-Object { $_.'@odata.type' -eq '#microsoft.graph.user' } | 
            Select-Object -ExpandProperty Id
        Write-Log "Current user members in destination group: $($currentMembers.Count)"
    } catch {
        $msg = "Failed to retrieve members for group $destGroupId. $_"
        Write-Log "ERROR: $msg"
        $ErrorSummary += $msg
        continue
    }

    # Determine users to add and remove
    $usersToAddNew = $usersToAdd | Where-Object { $currentMembers -notcontains $_ }
    $usersToRemove = $currentMembers | Where-Object { $usersToAdd -notcontains $_ }

    Write-Log "Users to add: $($usersToAddNew.Count), Users to remove: $($usersToRemove.Count)"

    # Batch add users
    if ($usersToAddNew.Count -gt 0) {
        Write-Log "Starting batch add operation for $($usersToAddNew.Count) users..."
        $addedCount = Add-UsersToGroupBatch -GroupId $destGroupId -UserIds $usersToAddNew
        $UsersAdded += $addedCount
        Write-Log "Successfully added $addedCount users to group $destGroupId"
    }

    # Batch remove users
    if ($usersToRemove.Count -gt 0) {
        Write-Log "Starting batch remove operation for $($usersToRemove.Count) users..."
        $removedCount = Remove-UsersFromGroupBatch -GroupId $destGroupId -UserIds $usersToRemove
        $UsersRemoved += $removedCount
        Write-Log "Successfully removed $removedCount users from group $destGroupId"
    }
}

# Prepare summary
$SummaryBody = @"
Autopatch Sync Summary:
=======================
Execution Time: $(Get-Date -Format "yyyy-MM-dd HH:mm:ss")
Devices Processed: $DevicesProcessed
Users Added: $UsersAdded
Users Removed: $UsersRemoved
Errors: $($ErrorSummary.Count)

Full Log:
$($script:LogEntries -join "`r`n")
"@

Write-Log "=== Synchronization Complete ==="
Write-Log "Total Devices Processed: $DevicesProcessed"
Write-Log "Total Users Added: $UsersAdded"
Write-Log "Total Users Removed: $UsersRemoved"
Write-Log "Total Errors: $($ErrorSummary.Count)"

# Email logic
if ($EmailMode -eq "Summary") {
    Send-Email -Subject "Autopatch Sync Summary - $(Get-Date -Format 'yyyy-MM-dd')" -Body $SummaryBody
} elseif ($EmailMode -eq "ErrorsOnly" -and $ErrorSummary.Count -gt 0) {
    $ErrorDetails = ($ErrorSummary -join "`r`n")
    $ErrorBody = @"
Autopatch Sync Errors:
======================
Execution Time: $(Get-Date -Format "yyyy-MM-dd HH:mm:ss")
Devices Processed: $DevicesProcessed
Users Added: $UsersAdded
Users Removed: $UsersRemoved
Errors: $($ErrorSummary.Count)

Error Details:
$ErrorDetails

Full Log:
$($script:LogEntries -join "`r`n")
"@
    Send-Email -Subject "Autopatch Sync Errors - $(Get-Date -Format 'yyyy-MM-dd')" -Body $ErrorBody
}

Write-Output "Script execution completed. Check Azure Automation job logs for details."
