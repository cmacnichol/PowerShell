<#
.SYNOPSIS
Unit tests for AWS Lambda WorkSpaces tagging script using Pester.

.DESCRIPTION
Validates:
- New workspace logic (Identity Store lookup required)
- Rebuild logic (Identity Store lookup skipped)
- Running mode change
- Access eventData
- Unhandled eventData type
Mocks AWS cmdlets to avoid real API calls.

.NOTES
Author: Your Name
Date: 2025-11-21
Requires: Pester
#>


# --- Dummy stubs for AWS cmdlets (so mocks work without modules) ---
function Get-IDSUser {}
function Get-WksTag {}
function New-WKSTag {}

Describe "Lambda WorkSpaces Handler Tests" {
    $IdentityStoreId = "d-1234567890"
    $workspaceId = "ws-abcdef123"
    $mockUser = @{
        UserName = "testuser@test.com"
        Emails = @(@{Value="testuser@example.com"})
        Attributes = @(@{AttributePath="department";AttributeValue="IT"})
    }

    
    BeforeAll {
        . "$PSScriptRoot\Lambda-WorkSpacesHandlerFunc.ps1"
    }

    BeforeEach {
        # Reset mocks before each test
        Mock Get-IDSUser { return $mockUser }
        Mock Get-WksTag { return @{ Tags = @{} } }
        Mock New-WKSTag { return $true }
    }

    Context "Workspace State Change - New Workspace" {
        It "Should lookup user and apply Create_Date tag" {

            $eventData = @{
                version = "0"
                id = "example-event-id"
                'detail-type' = "WorkSpaces Workspace State Change"
                source = "aws.workspaces"
                account = "123456789012"
                time = "2025-11-23T20:40:00Z"
                region = "us-east-1"
                resources = @("arn:aws:workspaces:us-east-1:123456789012:workspace/ws-xxxxxx")
                detail = @{
                    state = "PENDING"
                    userName = "testuser@test.com"
                    runningMode = "AUTO_STOP"
                    workspaceId = "ws-xxxxxx"
                    directoryId = "d-yyyyyy"
                    bundleId = "wsb-zzzzzz"
                }
            }

            $result = Invoke-LambdaHandler -eventData $eventData -IdentityStoreId $IdentityStoreId -ReturnLogsForTesting
            
            Assert-MockCalled Get-IDSUser -Exactly 1
            Assert-MockCalled New-WKSTag -Exactly 1

            $logJson = $result | ConvertFrom-Json
            ($logJson | Where-Object { $_.Action -eq "ApplyingTags" }) | Should -Not -BeNullOrEmpty
            ($logJson | Where-Object { $_.Action -eq "WorkspaceStateChangeComplete" }).Details.Status | Should -Be "TagsApplied"
            # Fix: Access Details.Create_Date directly, not Details.Tags
            ($logJson | Where-Object { $_.Action -eq "ApplyingTags" }).Details.Create_Date | Should -Not -BeNullOrEmpty
        }
    }

    Context "Workspace State Change - Rebuild" {
        It "Should NOT lookup user and apply LastRebuildDate tag" {
            # Simulate existing Create_Date tag
            Mock Get-WksTag { return @{ Tags = @{ "Create_Date" = "2025-01-01" } } }

            $eventData = @{
                'detail-type' = "WorkSpaces Workspace State Change"
                detail = @{
                    state = "PENDING"
                    userName = "testuser"
                    runningMode = "AUTO_STOP"
                    workspaceId = $workspaceId
                }
            }

            $result = Invoke-LambdaHandler -eventData $eventData -IdentityStoreId $IdentityStoreId -ReturnLogsForTesting

            Assert-MockCalled Get-IDSUser -Exactly 0  # No lookup for rebuild
            Assert-MockCalled New-WKSTag -Exactly 1

            $logJson = $result | ConvertFrom-Json
            ($logJson | Where-Object { $_.Action -eq "ApplyingTags" }).Details.LastRebuildDate | Should -Not -BeNullOrEmpty
            ($logJson | Where-Object { $_.Action -eq "ApplyingTags" }).Details.Running_Mode | Should -Be "AUTO_STOP"
            # Fix: Remove the incorrect .Tags reference
            # This assertion was checking a non-existent property
        }
    }

    Context "Workspace RunningMode Change" {
        It "Should update Running_Mode tag" {
            $eventData = @{
                'detail-type' = "WorkSpaces Workspace RunningMode Change"
                detail = @{
                    runningMode = "ALWAYS_ON"
                    workspaceId = $workspaceId
                }
            }

            $result = Invoke-LambdaHandler -eventData $eventData -IdentityStoreId $IdentityStoreId -ReturnLogsForTesting

            Assert-MockCalled New-WKSTag -Exactly 1
            $logJson = $result | ConvertFrom-Json
            ($logJson | Where-Object { $_.Action -eq "RunningModeChange" }) | Should -Not -BeNullOrEmpty
            ($logJson | Where-Object { $_.Action -eq "RunningModeUpdateComplete" }).Details.Status | Should -Be "TagsUpdated"
        }
    }

    Context "WorkSpaces Access eventData" {
        It "Should update LastConnectionDate tag" {
            $eventData = @{
                'detail-type' = "WorkSpaces Access"
                detail = @{
                    timestamp = (Get-Date).ToString()
                    workspaceId = $workspaceId
                }
            }

            $result = Invoke-LambdaHandler -eventData $eventData -IdentityStoreId $IdentityStoreId -ReturnLogsForTesting

            Assert-MockCalled New-WKSTag -Exactly 1
            
            $logJson = $result | ConvertFrom-Json
            
            ($logJson | Where-Object { $_.Action -eq "LoginEventData" }).Details.LastConnectionDate | Should -Not -BeNullOrEmpty
        }
    }

    Context "Unhandled eventData Type" {
        It "Should log warning for unknown eventData type" {
            $eventData = @{
                'detail-type' = "Unknown eventData"
                detail = @{
                    workspaceId = $workspaceId
                }
            }

            $result = Invoke-LambdaHandler -eventData $eventData -IdentityStoreId $IdentityStoreId -ReturnLogsForTesting

            $logJson = $result | ConvertFrom-Json
            ($logJson | Where-Object { $_.Action -eq "UnhandledEventDataType" }).Level | Should -Be "WARN"
        }
    }

    Context "Error Handling" {
        It "Should handle Get-WksTag failure gracefully" {
            Mock Get-WksTag { throw "API Error: Unable to retrieve tags" }
            
            $eventData = @{
                'detail-type' = "WorkSpaces Workspace State Change"
                detail = @{
                    state = "PENDING"
                    userName = "testuser@test.com"
                    runningMode = "AUTO_STOP"
                    workspaceId = $workspaceId
                }
            }

            { Invoke-LambdaHandler -eventData $eventData -IdentityStoreId $IdentityStoreId -ReturnLogsForTesting } | Should -Throw
            
            # Verify error was logged
            Assert-MockCalled Get-WksTag -Exactly 1
        }

        It "Should handle Get-IDSUser failure for new workspace" {
            Mock Get-IDSUser { throw "User not found in Identity Store" }
            
            $eventData = @{
                'detail-type' = "WorkSpaces Workspace State Change"
                detail = @{
                    state = "PENDING"
                    userName = "nonexistent@test.com"
                    runningMode = "AUTO_STOP"
                    workspaceId = $workspaceId
                }
            }

            { Invoke-LambdaHandler -eventData $eventData -IdentityStoreId $IdentityStoreId -ReturnLogsForTesting } | Should -Throw
        }

        It "Should handle New-WKSTag failure" {
            Mock New-WKSTag { throw "Failed to apply tags" }
            
            $eventData = @{
                'detail-type' = "WorkSpaces Workspace RunningMode Change"
                detail = @{
                    runningMode = "ALWAYS_ON"
                    workspaceId = $workspaceId
                }
            }

            { Invoke-LambdaHandler -eventData $eventData -IdentityStoreId $IdentityStoreId -ReturnLogsForTesting } | Should -Throw
        }
    }

    Context "Edge Cases - User Data" {
        It "Should handle user with no email address" {
            Mock Get-IDSUser { 
                return @{
                    UserName = "testuser"
                    Emails = @()
                    Attributes = @(@{AttributePath="department";AttributeValue="IT"})
                }
            }
            
            $eventData = @{
                'detail-type' = "WorkSpaces Workspace State Change"
                detail = @{
                    state = "PENDING"
                    userName = "testuser"
                    runningMode = "AUTO_STOP"
                    workspaceId = $workspaceId
                }
            }

            $result = Invoke-LambdaHandler -eventData $eventData -IdentityStoreId $IdentityStoreId -ReturnLogsForTesting
            $logJson = $result | ConvertFrom-Json
            
            ($logJson | Where-Object { $_.Action -eq "ApplyingTags" }).Details.Email | Should -Be ""
        }

        It "Should handle user with no department attribute" {
            Mock Get-IDSUser { 
                return @{
                    UserName = "testuser"
                    Emails = @(@{Value="testuser@example.com"})
                    Attributes = @()
                }
            }
            
            $eventData = @{
                'detail-type' = "WorkSpaces Workspace State Change"
                detail = @{
                    state = "PENDING"
                    userName = "testuser"
                    runningMode = "AUTO_STOP"
                    workspaceId = $workspaceId
                }
            }

            $result = Invoke-LambdaHandler -eventData $eventData -IdentityStoreId $IdentityStoreId -ReturnLogsForTesting
            $logJson = $result | ConvertFrom-Json
            
            ($logJson | Where-Object { $_.Action -eq "ApplyingTags" }).Details.Department | Should -BeNullOrEmpty
        }

        It "Should handle user with multiple email addresses" {
            Mock Get-IDSUser { 
                return @{
                    UserName = "testuser"
                    Emails = @(
                        @{Value="primary@example.com"}
                        @{Value="secondary@example.com"}
                    )
                    Attributes = @(@{AttributePath="department";AttributeValue="IT"})
                }
            }
            
            $eventData = @{
                'detail-type' = "WorkSpaces Workspace State Change"
                detail = @{
                    state = "PENDING"
                    userName = "testuser"
                    runningMode = "AUTO_STOP"
                    workspaceId = $workspaceId
                }
            }

            $result = Invoke-LambdaHandler -eventData $eventData -IdentityStoreId $IdentityStoreId -ReturnLogsForTesting
            $logJson = $result | ConvertFrom-Json
            
            # Should use first email
            ($logJson | Where-Object { $_.Action -eq "ApplyingTags" }).Details.Email | Should -Be "primary@example.com"
        }
    }

    Context "Edge Cases - Event States" {
        It "Should ignore non-PENDING workspace state changes" {
            $eventData = @{
                'detail-type' = "WorkSpaces Workspace State Change"
                detail = @{
                    state = "AVAILABLE"
                    userName = "testuser"
                    runningMode = "AUTO_STOP"
                    workspaceId = $workspaceId
                }
            }

            $result = Invoke-LambdaHandler -eventData $eventData -IdentityStoreId $IdentityStoreId -ReturnLogsForTesting
            
            # Should not call any AWS functions
            Assert-MockCalled Get-IDSUser -Exactly 0
            Assert-MockCalled Get-WksTag -Exactly 0
            Assert-MockCalled New-WKSTag -Exactly 0
        }
    }

    Context "Invalid Input Validation" {
        It "Should throw error when EventData is null" {
            { Invoke-LambdaHandler -EventData $null -IdentityStoreId $IdentityStoreId -ReturnLogsForTesting } | Should -Throw "Invalid EventData structure"
        }

        It "Should throw error when EventData has no detail property" {
            $eventData = @{
                'detail-type' = "WorkSpaces Access"
            }
            
            { Invoke-LambdaHandler -EventData $eventData -IdentityStoreId $IdentityStoreId -ReturnLogsForTesting } | Should -Throw "Invalid EventData structure"
        }
    }

    Context "Logging Validation" {
        It "Should log all expected actions for new workspace flow" {
            $eventData = @{
                'detail-type' = "WorkSpaces Workspace State Change"
                detail = @{
                    state = "PENDING"
                    userName = "testuser@test.com"
                    runningMode = "AUTO_STOP"
                    workspaceId = $workspaceId
                }
            }

            $result = Invoke-LambdaHandler -eventData $eventData -IdentityStoreId $IdentityStoreId -ReturnLogsForTesting
            $logJson = $result | ConvertFrom-Json
            
            $logJson.Count | Should -BeGreaterThan 3
            ($logJson | Where-Object { $_.Action -eq "WorkspaceStateChangeStart" }) | Should -Not -BeNullOrEmpty
            ($logJson | Where-Object { $_.Action -eq "NewWorkspaceDetected" }) | Should -Not -BeNullOrEmpty
            ($logJson | Where-Object { $_.Action -eq "UserLookupComplete" }) | Should -Not -BeNullOrEmpty
            ($logJson | Where-Object { $_.Action -eq "ApplyingTags" }) | Should -Not -BeNullOrEmpty
            ($logJson | Where-Object { $_.Action -eq "WorkspaceStateChangeComplete" }) | Should -Not -BeNullOrEmpty
        }

        It "Should include timestamp and level in all log entries" {
            $eventData = @{
                'detail-type' = "WorkSpaces Workspace RunningMode Change"
                detail = @{
                    runningMode = "ALWAYS_ON"
                    workspaceId = $workspaceId
                }
            }

            $result = Invoke-LambdaHandler -eventData $eventData -IdentityStoreId $IdentityStoreId -ReturnLogsForTesting
            $logJson = $result | ConvertFrom-Json
            
            foreach ($log in $logJson) {
                $log.Timestamp | Should -Not -BeNullOrEmpty
                $log.Level | Should -Not -BeNullOrEmpty
                $log.WorkspaceId | Should -Be $workspaceId
            }
        }
    }

    Context "Different Running Modes" {
        It "Should tag new workspace with ALWAYS_ON mode" {
            $eventData = @{
                'detail-type' = "WorkSpaces Workspace State Change"
                detail = @{
                    state = "PENDING"
                    userName = "testuser@test.com"
                    runningMode = "ALWAYS_ON"
                    workspaceId = $workspaceId
                }
            }

            $result = Invoke-LambdaHandler -eventData $eventData -IdentityStoreId $IdentityStoreId -ReturnLogsForTesting
            $logJson = $result | ConvertFrom-Json
            
            ($logJson | Where-Object { $_.Action -eq "ApplyingTags" }).Details.Running_Mode | Should -Be "ALWAYS_ON"
        }

        It "Should update tag when mode changes from AUTO_STOP to ALWAYS_ON" {
            Mock Get-WksTag { return @{ Tags = @{ "Running_Mode" = "AUTO_STOP" } } }
            
            $eventData = @{
                'detail-type' = "WorkSpaces Workspace RunningMode Change"
                detail = @{
                    runningMode = "ALWAYS_ON"
                    workspaceId = $workspaceId
                }
            }

            $result = Invoke-LambdaHandler -eventData $eventData -IdentityStoreId $IdentityStoreId -ReturnLogsForTesting
            $logJson = $result | ConvertFrom-Json
            
            Assert-MockCalled New-WKSTag -Exactly 1
            ($logJson | Where-Object { $_.Action -eq "RunningModeChange" }).Details.Running_Mode | Should -Be "ALWAYS_ON"
        }
    }

    Context "Date Formatting" {
        It "Should format Create_Date as yyyy-MM-dd" {
            $eventData = @{
                'detail-type' = "WorkSpaces Workspace State Change"
                detail = @{
                    state = "PENDING"
                    userName = "testuser@test.com"
                    runningMode = "AUTO_STOP"
                    workspaceId = $workspaceId
                }
            }

            $result = Invoke-LambdaHandler -eventData $eventData -IdentityStoreId $IdentityStoreId -ReturnLogsForTesting
            $logJson = $result | ConvertFrom-Json
            
            $createDate = ($logJson | Where-Object { $_.Action -eq "ApplyingTags" }).Details.Create_Date
            $createDate | Should -Match "^\d{4}-\d{2}-\d{2}$"
        }

        It "Should format LastConnectionDate with time" {
            $testTimestamp = "2025-11-23T15:30:45Z"
            
            $eventData = @{
                'detail-type' = "WorkSpaces Access"
                detail = @{
                    timestamp = $testTimestamp
                    workspaceId = $workspaceId
                }
            }

            $result = Invoke-LambdaHandler -eventData $eventData -IdentityStoreId $IdentityStoreId -ReturnLogsForTesting
            $logJson = $result | ConvertFrom-Json
            
            $lastConnection = ($logJson | Where-Object { $_.Action -eq "LoginEventData" }).Details.LastConnectionDate
            $lastConnection | Should -Match "^\d{4}-\d{2}-\d{2} \d{2}:\d{2}:\d{2}$"
        }
    }
}
