<#
.SYNOPSIS
AWS Lambda PowerShell script to process WorkSpaces events and apply tags dynamically.

.DESCRIPTION
Handles AWS WorkSpaces-related events in Lambda:
- Workspace creation or rebuild
- Running mode changes
- Access events (login)
Applies tags to WorkSpaces resources and logs actions in structured JSON format for CloudWatch.

.PARAMETER Event
The AWS Lambda event object containing WorkSpaces details.

.PARAMETER IdentityStoreId
The AWS Identity Store ID used to look up user details (only for new WorkSpaces).

.EXAMPLE
Invoke-LambdaHandler -Event $event -IdentityStoreId "d-1234567890"

.NOTES
Author: NAME
Date: 2025-11-21
Version: 2.1
Requires: AWS.Tools.WorkSpaces, AWS.Tools.IdentityStore
#>
[CmdletBinding()]
param(
    [Parameter(Position=0)]$EventData,
    [Parameter(Position=1)]$IdentityStoreId,
    [Parameter(Position=2)][switch]$ReturnLogsForTesting  # Add parameter for Pester tests
)

if (-not $EventData -or -not $EventData.detail) {
    throw "Invalid EventData structure"
}

$tagData = @()
    
Import-Module AWS.Tools.WorkSpaces
Import-Module AWS.Tools.IdentityStore

$workspaceId = $EventData.detail.workspaceId
$EventDataType = $EventData['detail-type']
$script:logs = @() # Collect logs for Pester validation

function Write-awslog {
    param([string]$Action, [hashtable]$Details, [string]$Level = "INFO")
    $logEntry = @{
        Timestamp     = (Get-Date).ToString("o")
        EventDataType = $EventDataType
        WorkspaceId   = $workspaceId
        Action        = $Action
        Level         = $Level
        Details       = $Details
    }
        
    # Add to collection for testing
    $script:logs += $logEntry
        
    # Write to CloudWatch (stdout in Lambda) - only if not in test mode
    if (-not $ReturnLogsForTesting) {
        $logJson = $logEntry | ConvertTo-Json -Depth 10 -Compress
        Write-Host $logJson
    }
}

switch ($EventDataType) {
    "WorkSpaces Workspace State Change" {
        if ($EventData.detail.state -eq "PENDING") {

            $userName = $EventData.detail.userName
            $runningMode = $EventData.detail.runningMode
            $currentDate = (Get-Date).ToString("yyyy-MM-dd")

            Write-awslog -Action "WorkspaceStateChangeStart" -Details @{UserName = $userName; RunningMode = $runningMode }

            # Check existing tags
            try {
                $existingTags = (Get-WksTag -WorkspaceId $workspaceId -ErrorAction Stop).Tags
            }
            catch {
                Write-awslog -Action "GetTagsFailed" -Details @{Error = $_.Exception.Message } -Level "ERROR"
                throw
            }

            $createDateExists = $existingTags.ContainsKey("Create_Date")

            if ($createDateExists) {
                # Rebuild detected
                Write-awslog -Action "RebuildDetected" -Details @{ExistingCreateDate = $existingTags["Create_Date"] }
                $tagData = @{
                    "LastRebuildDate" = $currentDate
                    "Running_Mode"    = $runningMode
                }
            }
            else {
                # New workspace
                Write-awslog -Action "NewWorkspaceDetected" -Details @{}

                $user = Get-IDSUser -IdentityStoreId $IdentityStoreId -UserId $userName
                    
                $emailAddress = if ($user.Emails.Count -gt 0) { $user.Emails[0].Value } else { "" }
                $department = ($user.Attributes | Where-Object { $_.AttributePath -eq "department" }).AttributeValue
                    
                Write-awslog -Action "UserLookupComplete" -Details @{Email = $emailAddress; Department = $department }

                $tagData = @{
                    "Create_Date"  = $currentDate
                    "Email"        = $emailAddress
                    "Department"   = $department
                    "Running_Mode" = $runningMode
                }
            }
                
            $tags = foreach ($key in $tagData.Keys) {
                New-Object Amazon.WorkSpaces.Model.Tag -Property @{ Key = $key; Value = $tagData[$key] }
            }

            Write-awslog -Action "ApplyingTags" -Details $tagData
            New-WKSTag -WorkspaceId $workspaceId -Tags $tags | Out-Null
            Write-awslog -Action "WorkspaceStateChangeComplete" -Details @{Status = "TagsApplied" }
        }
    }
    "WorkSpaces Workspace RunningMode Change" {
        $newMode = $EventData.detail.runningMode
        $tags = New-Object Amazon.WorkSpaces.Model.Tag -Property @{ Key = "Running_Mode"; Value = $newMode }
        Write-awslog -Action "RunningModeChange" -Details @{Running_Mode = $newMode }
        New-WKSTag -WorkspaceId $workspaceId -Tags $tags | Out-Null
        Write-awslog -Action "RunningModeUpdateComplete" -Details @{Status = "TagsUpdated" }
    }
    "WorkSpaces Access" {
        $lastLogin = (Get-Date $EventData.detail.timestamp).ToString("yyyy-MM-dd HH:mm:ss")
        $tags = New-Object Amazon.WorkSpaces.Model.Tag -Property @{ Key = "LastConnectionDate"; Value = $lastLogin }
        Write-awslog -Action "LoginEventData" -Details @{LastConnectionDate = $lastLogin }
        New-WKSTag -WorkspaceId $workspaceId -Tags $tags | Out-Null
        Write-awslog -Action "LoginTagUpdateComplete" -Details @{Status = "TagsUpdated" }
    }
    default {
        Write-awslog -Action "UnhandledEventDataType" -Details @{EventDataType = $EventDataType } -Level "WARN"
    }
}

# Return logs only for Pester testing
if ($ReturnLogsForTesting) {
    return ($script:logs | ConvertTo-Json -Depth 10 -Compress)
}