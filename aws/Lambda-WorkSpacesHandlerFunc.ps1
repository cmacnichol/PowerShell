function Invoke-WorkspacesLambdaHandler {
<#
.SYNOPSIS
AWS Lambda function handler for automating WorkSpaces tagging based on EventBridge events.

.DESCRIPTION
This Lambda function automatically tags AWS WorkSpaces based on lifecycle events captured by EventBridge.
It handles three event types:
1. Workspace State Change (PENDING) - Tags new workspaces or rebuilds with user info and dates
2. Workspace RunningMode Change - Updates Running_Mode tag when compute mode changes
3. Workspace Access - Updates LastConnectionDate tag when users connect

The function integrates with AWS Identity Store to retrieve user metadata (email, department) for new workspaces.
For workspace rebuilds, it skips Identity Store lookup and only updates the LastRebuildDate.

All actions are logged in structured JSON format to CloudWatch Logs for monitoring and troubleshooting.

.PARAMETER EventData
The EventBridge event object passed from the Lambda trigger. Must contain:
- detail-type: Type of WorkSpaces event
- detail: Event-specific details including workspaceId, state, userName, runningMode, or timestamp

.PARAMETER IdentityStoreId
The ID of the AWS Identity Store instance (e.g., "d-1234567890") used to lookup user information.
Required for retrieving email addresses and department data for new workspace provisioning.

.PARAMETER ReturnLogsForTesting
Switch parameter used by Pester tests to return collected logs as JSON instead of writing to CloudWatch.
Do not use in production Lambda deployments.

.EXAMPLE
# Example EventBridge event for new workspace (PENDING state)
$event = @{
    'detail-type' = "WorkSpaces Workspace State Change"
    detail = @{
        state = "PENDING"
        userName = "user@example.com"
        runningMode = "AUTO_STOP"
        workspaceId = "ws-abc123def456"
    }
}
Invoke-WorkspacesLambdaHandler -EventData $event -IdentityStoreId "d-1234567890"

.EXAMPLE
# Example EventBridge event for workspace rebuild (existing Create_Date tag)
$event = @{
    'detail-type' = "WorkSpaces Workspace State Change"
    detail = @{
        state = "PENDING"
        userName = "user@example.com"
        runningMode = "AUTO_STOP"
        workspaceId = "ws-abc123def456"
    }
}
# If workspace already has Create_Date tag, function will:
# - Skip Identity Store lookup
# - Add LastRebuildDate tag instead
# - Update Running_Mode tag
Invoke-WorkspacesLambdaHandler -EventData $event -IdentityStoreId "d-1234567890"

.EXAMPLE
# Example EventBridge event for running mode change
$event = @{
    'detail-type' = "WorkSpaces Workspace RunningMode Change"
    detail = @{
        runningMode = "ALWAYS_ON"
        workspaceId = "ws-abc123def456"
    }
}
Invoke-WorkspacesLambdaHandler -EventData $event -IdentityStoreId "d-1234567890"

.EXAMPLE
# Example EventBridge event for user login
$event = @{
    'detail-type' = "WorkSpaces Access"
    detail = @{
        timestamp = "2025-11-23T15:30:45Z"
        workspaceId = "ws-abc123def456"
    }
}
Invoke-WorkspacesLambdaHandler -EventData $event -IdentityStoreId "d-1234567890"

.EXAMPLE
# Pester testing mode (returns logs for validation)
$event = @{ 'detail-type' = "WorkSpaces Access"; detail = @{ timestamp = "2025-11-23T15:30:45Z"; workspaceId = "ws-test" } }
$logs = Invoke-WorkspacesLambdaHandler -EventData $event -IdentityStoreId "d-1234567890" -ReturnLogsForTesting
$logData = $logs | ConvertFrom-Json

.INPUTS
None. This function does not accept pipeline input.

.OUTPUTS
None in production mode. Logs are written to CloudWatch via Write-Host.
System.String (JSON) when -ReturnLogsForTesting is specified for Pester validation.

.NOTES
Author: Christopher Macnichol
Version: 25.11.23
Last Modified: 2025-11-23

Change:
25.11.23 - Christopher Macnichol - Initial release.  Not Yet Tested in AWS Lambda.

Requires: 
- PowerShell 7.0+
- AWS.Tools.WorkSpaces
- AWS.Tools.IdentityStore
- AWS Lambda PowerShell Runtime

Event Sources:
- EventBridge rule matching "WorkSpaces Workspace State Change"
- EventBridge rule matching "WorkSpaces Workspace RunningMode Change"  
- EventBridge rule matching "WorkSpaces Access"

Tags Applied:
New Workspace:
  - Create_Date (yyyy-MM-dd)
  - Email (user primary email from Identity Store)
  - Department (from Identity Store attributes)
  - Running_Mode (AUTO_STOP or ALWAYS_ON)

Workspace Rebuild:
  - LastRebuildDate (yyyy-MM-dd)
  - Running_Mode (AUTO_STOP or ALWAYS_ON)

Running Mode Change:
  - Running_Mode (updated value)

User Access:
  - LastConnectionDate (yyyy-MM-dd HH:mm:ss)

IAM Permissions Required:
- workspaces:DescribeWorkspaces
- workspaces:DescribeTags
- workspaces:CreateTags
- identitystore:DescribeUser
- logs:CreateLogGroup
- logs:CreateLogStream
- logs:PutLogEvents

.LINK
https://docs.aws.amazon.com/workspaces/latest/adminguide/cloudwatch-events.html

.LINK
https://docs.aws.amazon.com/lambda/latest/dg/powershell-handler.html

.LINK
https://docs.aws.amazon.com/cli/latest/reference/workspaces/create-tags.html
#>
    param(
        [Parameter()]$EventData,
        [Parameter()]$IdentityStoreId,
        [Parameter()][switch]$ReturnLogsForTesting  # Add parameter for Pester tests
    )

    if (-not $EventData -or -not $EventData.detail) {
        throw "Invalid EventData structure"
    }

    $tagData = @()
    
    Import-Module AWS.Tools.WorkSpaces
    Import-Module AWS.Tools.IdentityStore

    $workspaceId = $EventData.detail.workspaceId
    $EventDataType   = $EventData['detail-type']
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

                $userName    = $EventData.detail.userName
                $runningMode = $EventData.detail.runningMode
                $currentDate = (Get-Date).ToString("yyyy-MM-dd")

                Write-awslog -Action "WorkspaceStateChangeStart" -Details @{UserName=$userName;RunningMode=$runningMode}

                # Check existing tags
                try {
                    $existingTags = (Get-WksTag -WorkspaceId $workspaceId -ErrorAction Stop).Tags
                }
                catch {
                    Write-awslog -Action "GetTagsFailed" -Details @{Error=$_.Exception.Message} -Level "ERROR"
                    throw
                }

                $createDateExists = $existingTags.ContainsKey("Create_Date")

                if ($createDateExists) {
                    # Rebuild detected
                    Write-awslog -Action "RebuildDetected" -Details @{ExistingCreateDate=$existingTags["Create_Date"]}
                    $tagData = @{
                        "LastRebuildDate" = $currentDate
                        "Running_Mode"    = $runningMode
                    }
                } else {
                    # New workspace
                    Write-awslog -Action "NewWorkspaceDetected" -Details @{}

                    $user = Get-IDSUser -IdentityStoreId $IdentityStoreId -UserId $userName
                    
                    $emailAddress = if ($user.Emails.Count -gt 0) { $user.Emails[0].Value } else { "" }
                    $department   = ($user.Attributes | Where-Object { $_.AttributePath -eq "department" }).AttributeValue
                    
                    Write-awslog -Action "UserLookupComplete" -Details @{Email=$emailAddress;Department=$department}

                    $tagData = @{
                        "Create_Date"     = $currentDate
                        "Email"           = $emailAddress
                        "Department"      = $department
                        "Running_Mode"    = $runningMode
                    }
                }
                
                $tags = foreach ($key in $tagData.Keys) {
                    New-Object Amazon.WorkSpaces.Model.Tag -Property @{ Key = $key; Value = $tagData[$key] }
                }

                Write-awslog -Action "ApplyingTags" -Details $tagData
                New-WKSTag -WorkspaceId $workspaceId -Tags $tags | Out-Null
                Write-awslog -Action "WorkspaceStateChangeComplete" -Details @{Status="TagsApplied"}
            }
        }
        "WorkSpaces Workspace RunningMode Change" {
            $newMode = $EventData.detail.runningMode
            $tags = New-Object Amazon.WorkSpaces.Model.Tag -Property @{ Key = "Running_Mode"; Value = $newMode }
            Write-awslog -Action "RunningModeChange" -Details @{Running_Mode=$newMode}
            New-WKSTag -WorkspaceId $workspaceId -Tags $tags | Out-Null
            Write-awslog -Action "RunningModeUpdateComplete" -Details @{Status="TagsUpdated"}
        }
        "WorkSpaces Access" {
            $lastLogin = (Get-Date $EventData.detail.timestamp).ToString("yyyy-MM-dd HH:mm:ss")
            $tags = New-Object Amazon.WorkSpaces.Model.Tag -Property @{ Key = "LastConnectionDate"; Value = $lastLogin }
            Write-awslog -Action "LoginEventData" -Details @{LastConnectionDate=$lastLogin}
            New-WKSTag -WorkspaceId $workspaceId -Tags $tags | Out-Null
            Write-awslog -Action "LoginTagUpdateComplete" -Details @{Status="TagsUpdated"}
        }
        default {
            Write-awslog -Action "UnhandledEventDataType" -Details @{EventDataType=$EventDataType} -Level "WARN"
        }
    }

    # Return logs only for Pester testing
    if ($ReturnLogsForTesting) {
        return ($script:logs | ConvertTo-Json -Depth 10 -Compress)
    }
}

Invoke-WorkspacesLambdaHandler -EventData $event -IdentityStoreId $Env:IDENTITY_STORE_ID -ReturnLogsForTesting:$false