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
[cmdletbinding]

$Popup = New-Object -ComObject wscript.shell

Function End-MultiThread-Script {
	Param ($threadcount)
	$end = $false
	Do {
		Start-Sleep 1
		$EndScriptCount = 1
		for ($i = 0; $i -le $threadcount; $i++) {If ($SyncTable.Runspaces["Handle$i"].IsCompleted -eq $true) {$EndScriptCount++}}
		$CancelScript = $SyncTable.CancelScript
		If ($EndScriptCount -gt $threadcount -or $CancelScript -eq $true) {
			for ($i = 0; $i -le $threadcount; $i++) {
				$Synctable.Runspaces["Script$i"].EndInvoke($Synctable.Runspaces["Handle$i"])
				$Synctable.Runspaces["Script$i"].Dispose()
				$Synctable.Runspaces["$i"].Close()
				$Synctable.Runspaces["$i"] = $null
				$Synctable.Runspaces["Script$i"] = $null
			}
			$SyncTable.Runspaces = $null
			$SyncTable.RunspacePool.Close()
			Get-Variable -Exclude Synctable | Remove-Variable -ErrorAction SilentlyContinue
			[System.GC]::Collect()
			$SyncTable.StopUpdateData = $true
			$Finished = $true
		}
		else {
			[System.Threading.Mutex]$Mutex
			Try {
				[Bool]$Created = $false
				$Mutex = New-Object System.Threading.Mutex($true, 'MyMutex', [ref] $Created)
				If (!$Created) {$Mutex.WaitOne()}
				$InProgArray = $SyncTable.ThreadsInProg
				$CurrentTime = Get-Date
			}
			Finally {
				$Mutex.ReleaseMutex()
				$Mutex.Dispose()
			}
			Foreach ($instance in $InProgArray) {
				$StartTime = $instance.StartTime
				$CompareTimes = $CurrentTime - $StartTime
				$Minutes = $CompareTimes.Minutes
				$Seconds = $CompareTimes.Seconds + ($Minutes * 60)
				If ($Seconds -gt $Timeout) {
					$ThreadNumber = $instance.ThreadNumber
					$SyncTable.Runspaces["Script$ThreadNumber"].Dispose()
					$SyncTable.Runspaces["$ThreadNumber"].Close()
					$CancelComp = $instance.CompName
					Log "Collecting information on $CancelComp took longer than $timeout seconds... Cancelling job"
					$SyncTable.Runspaces["Script$ThreadNumber"] = [Powershell]::Create().AddScript($Scriptblock).AddArgument($ThreadNumber)
					$Synctable.Runspaces["Script$ThreadNumber"].RunspacePool = $SyncTable.RunspacePool
					$Synctable.Runspaces["Handle$ThreadNumber"] = $Synctable.Runspaces["Script$ThreadNumber"].BeginInvoke()
				}
			}
		}
		$InProg = $InProgArray.Count
		If ($Finished -ne $true) {Log "Still working! $InProg threads in progress. Threads will close if inactive for more than $timeout seconds."}
	} While ($end -ne $true)
}

Function Pause-Jobs {
	do {
		$RunningJobs = 0
		$IgnoredJobs = 0
		Get-Job | Where-Object {$_.State -eq 'Running'} | ForEach-Object {
			$JobID = $_.ID
			if ($Script:SkippedJobs -inotcontains "$JobID") {
				$RunningJobs++
				$CurrTime = Get-Date
				$CurrentTime = $CurrTime.ToLongTimeString()
				$CompName = $_.Name
				$StartTime = $JobTimer["$CompName"]
				$CompareTime = $CurrTime - $StartTime
				if ($CompareTime.Minutes -gt 2 -and $IgnoredJobs -eq 0){
					$Script:SkippedJobs += @("$JobID")
					$IgnoredJobs++
					Log -Message "$CompName timed out..."
					$NewRecord = Select-Object -InputObject '' Name
					$NewRecord.Name = $CompName
					$Script:TimedOutComps += $NewRecord
				}
			}
		}
		if ($RunningJobs -gt $Script:MaxJobs) {
			$AddToMaxJobs = 1
			Start-Sleep 1
			Log -Message 'Waiting on some jobs to finish before continuing...'
		}
	} while ($RunningJobs -gt $MaxJobs -and $Script:Synctable.CancelScript -ne $true)
	if ($AddToMaxJobs -eq 1 -and $MaxJobs -lt 20) {
		$Script:MaxJobs = $Script:MaxJobs + 5
	}
}

Function StartThreads {
	Param (
		$ScriptBlock,
		$Threads = 15
	)
	$SyncTable.ThreadsInProg = New-Object System.Collections.ArrayList
	$Synctable.Runspaces = @{}
	$SessionState = [System.Management.Automation.Runspaces.InitialSessionState]::CreateDefault()
	$SessionState.ApartmentState = 'STA'
	$SessionState.Variables.Add((New-Object -TypeName System.Management.Automation.Runspaces.SessionStateVariableEntry -ArgumentList 'SyncTable', $SyncTable, ''))
	$SyncTable.RunspacePool = [RunspaceFactory]::CreateRunspacePool(1, $Threads, $SessionState, $Host)
	$SyncTable.RunspacePool.Open()
	for ($i = 0; $i -lt $Threads; $i++) {
		$Synctable.Runspaces["Script$i"] = [Powershell]::Create().AddScript($Scriptblock).AddArgument($i).AddArgument($Directory)
		$Synctable.Runspaces["Script$i"].RunspacePool = $SyncTable.RunspacePool
		$Synctable.Runspaces["Handle$i"] = $Synctable.Runspaces["Script$i"].BeginInvoke()
	}
}

Function Pause-At-End {
	while (((get-job | where-object {$_.State -eq 'Running'}) | Measure-Object).Count -gt 0 -and $SyncTable.CancelScript -ne $true){
		Start-Sleep -Seconds 1
		Log -Message 'Waiting on the last few jobs to finish...'
	}
}

Function Pause-Script {
	$x = $false
	do {
		Start-Sleep 1
		if ($SyncTable.Window.IsVisible -eq $false -or $DeplSelSyncTable.Window.IsVisible -eq $false) {
			Start-Sleep 10
			$ProcessID = [System.Diagnostics.Process]::GetCurrentProcess()
			$ProcID = $ProcessID.ID
			& taskkill.exe /PID $ProcID /T /F
		}
	} while ($x -ne $true)
}

Function On_Close {
	$ProcessID = [System.Diagnostics.Process]::GetCurrentProcess()
	$ProcID = $ProcessID.ID
	& taskkill.exe /PID $ProcID /F
}

Function Log {
	Param ($Message, $ErrorMsg)
	$Synctable.UpdateLogText = $true
	$CurrTime = Get-Date
	$CurrentTime = $CurrTime.ToLongTimeString()
	$SyncTable.LogText = $SyncTable.LogText + "$CurrentTime - $Message $ErrorMsg`n"
}

Function MS_Exit_Click {
	$ProcessID = [System.Diagnostics.Process]::GetCurrentProcess()
	$ProcID = $ProcessID.ID
	& taskkill.exe /PID $ProcID /T /F
}

Function MS_About_Click {
	$ArgList = @()
	$ArgList += @("`"$Directory\SilentOpenPS.vbs`"")
	$ArgList += @("`"$Directory\About.ps1`"")
	Start-Process wscript.exe -ArgumentList $ArgList
}

Function Get-LocalGroup  {
[Cmdletbinding()] 
Param(
[Parameter(ValueFromPipeline=$True, ValueFromPipelineByPropertyName=$True)] 
[String[]]$Computername =  $Env:COMPUTERNAME,
[parameter()]
[string[]]$Group
)
Begin {

Function ConvertTo-SID {
Param([byte[]]$BinarySID)
(New-Object  System.Security.Principal.SecurityIdentifier($BinarySID,0)).Value
}

Function Get-LocalGroupMember {
Param ($Group)
$group.Invoke('members')  | ForEach {
$_.GetType().InvokeMember('Name',  'GetProperty',  $null,  $_, $null)
}
}
}

Process {
ForEach ($Computer in  $Computername) {
Try {
Write-Verbose "Connecting to $($Computer)"
$adsi = [ADSI]"WinNT://$Computer"

If ($PSBoundParameters.ContainsKey('Group')) {
Write-Verbose "Scanning for groups: $($Group -join ',')"
$Groups = ForEach  ($item in $group) {
$adsi.Children.Find($Item, 'Group')
}
} Else {
Write-Verbose  'Scanning all groups'
$groups = $adsi.Children | Where-Object {$_.SchemaClassName -eq 'group'}
}

If ($groups) {
$groups | ForEach {
[pscustomobject]@{
Computername = $Computer
Name = $_.Name[0]
Members = ((Get-LocalGroupMember  -Group $_))  -join ', '
SID = (ConvertTo-SID -BinarySID $_.ObjectSID[0])
}
}
} Else {
Throw 'No groups found!'
}
} Catch {
Write-Warning  "$($Computer): $_"
}
}
}
}

#Get-LocalGroup -Computername $env:COMPUTERNAME -Group 'Remote Desktop Users' -Verbose | Format-List

Function Btn_Start_Click {
Write-Verbose 'Start-Click Begin'

if ($SyncTable.UserList -eq $null){[System.Windows.Forms.MessageBox]::Show('User List in Empty.  Please enter at least one User ID.' , 'Missing User ID' , 0) | Out-Null; Exit}

	$RulesToSkip = $null
	$strMessage = "Do you want to add these users to $colname" + '?'
	$PopupAnswer = $Popup.Popup($strMessage,0,'Are you sure?',1)

	if ($PopupAnswer -eq 1) {
		$UserNameArray = $SyncTable.UserList
		$UserNameArray = $UserNameArray.Split("`n")
		$UserNameArray = $UserNameArray.Split("`r")
		$UserNameArray = $UserNameArray | Select-Object -Unique
		
		Log -Message 'Getting current user list for Computer: ' + $comp

        $users = Get-LocalGroup -Computername $SyncTable.CompList -Group 'Remote Desktop Users'

		foreach ($user in $users.Members) {

				if ($UserNameArray -icontains $user) {$UsersToSkip += @($user)}
		}
		
        #Log -Message "Starting to add rules..."

		foreach ($UserName in $UserNameArray) {

			if ($UsersToSkip -contains $UserName) {
				Log -Message "$UserName already exists in Group!"
				$Results = Select-Object -InputObject '' Name, Result
				$Results.Name = $UserName
				$Results.Result = 'User already exists'
				$Synctable.DataGridResults += $Results
			}
			elseif ($UserName -eq '') {}
			else {
				if ($UserName -ne $null) {

                    $domainuser = 'HBIUSERS\' + $UserName
                    $localgroup = 'Remote Desktop Users'

                    Log -Message "Adding $domainuser to $localgroup on $comp"

                    $objUser = [ADSI]("WinNT://$domainuser") 
                    $objGroup = [ADSI]("WinNT://$Workstation/$localgroup") 
                    $objGroup.PSBase.Invoke('Add',$objUser.PSBase.Path)

                            if ($Error[0]) {
								Log -Message "Error adding $Comp - $Error"
								$ErrorMessage = "$Error"
								$ErrorMessage = $ErrorMessage.Replace("`n",'')
								$Results = Select-Object -InputObject '' Name, Result
								$Results.Name = $CompName
								$Results.Result = "$ErrorMessage"
								$Synctable.DataGridResults += $Results
							}
							else {
								Log -Message "Successfully added $UserName"
								$Results = Select-Object -InputObject '' Name, Result
								$Results.Name = $CompName
								$Results.Result = 'Successfully Added'
								$Synctable.DataGridResults += $Results
							}
					}
					if ($ResourceID -eq $null) {
						Log -Message "Could not find $UserName - No rule added"
						$Results = Select-Object -InputObject '' Name, Result
						$Results.Name = $UserName
						$Results.Result = 'No Resource ID'
						$Synctable.DataGridResults += $Results
					}
				}
			}
		#}
	}
	Log -Message 'Finished!'
}


$Global:SyncTable = [HashTable]::Synchronized(@{})
$SyncTable.Host = $Host
$SyncTable.ColName = ': Remote Desktop Users' #$ColName
$SyncTable.Directory = $Directory
$Synctable.DataGridResults = New-Object System.Collections.Arraylist
$Runspace = [RunspaceFactory]::CreateRunspace()
$Runspace.ApartmentState = 'STA'
$Runspace.ThreadOptions = 'ReuseThread'
$Runspace.Open()
$Runspace.SessionStateProxy.SetVariable('SyncTable',$SyncTable)
$psScript = [Powershell]::Create().AddScript({

Add-Type -AssemblyName PresentationFramework,PresentationCore,WindowsBase

[XML]$xaml = @'
<Window
        xmlns="http://schemas.microsoft.com/winfx/2006/xaml/presentation"
        Title="Add Users to Group" Height="531.818" Width="475" ShowInTaskbar="False" WindowStartupLocation="CenterScreen">
    <Grid>
        <Menu Height="22" VerticalAlignment="Top">
            <MenuItem x:Name="MS_File" Header="File" Height="22">
                <MenuItem x:Name="MS_Exit" Header="Exit" Height="22"/>
            </MenuItem>
            <MenuItem x:Name="MS_Help" Header="Help" Height="22">
                <MenuItem x:Name="MS_About" Header="About" Height="22"/>
            </MenuItem>
        </Menu>
        <Label Name="Lbl_ColName" VerticalAlignment="Top" Content="" Margin="10,25,10,0" HorizontalContentAlignment="Center" VerticalContentAlignment="Center"/>
        <Label Content="User List" HorizontalAlignment="Left" Width="170" VerticalAlignment="Top" Margin="10,54,10,10" VerticalContentAlignment="Center" HorizontalContentAlignment="Center"/>
        <TextBox Name="Txt_UserList" TextWrapping="Wrap" AcceptsReturn="True" HorizontalAlignment="Left" Text="" Width="170" Margin="10,84,0,258" HorizontalScrollBarVisibility="Auto" VerticalScrollBarVisibility="Auto"/>
        <Label Content="Results" VerticalAlignment="Top" Margin="190,54,10,10" VerticalContentAlignment="Center" HorizontalContentAlignment="Center"/>
        <DataGrid Name="Grid_Results" Margin="190,83,10,122" IsReadOnly="True" AutoGenerateColumns="False" SelectionUnit="FullRow" HeadersVisibility="Column" ItemBindingGroup="{Binding}">
            <DataGrid.Columns>
                <DataGridTextColumn Binding="{Binding Path=Name}" Header="Name"/>
                <DataGridTextColumn Binding="{Binding Path=Result}" Header="Results" Width="*"/>
            </DataGrid.Columns>
        </DataGrid>
        <Label Content="Log" VerticalAlignment="Bottom" Margin="10,10,10,107" HorizontalContentAlignment="Center" VerticalContentAlignment="Center"/>
        <TextBox Name="Txt_Log" TextWrapping="NoWrap" AcceptsReturn="True" IsReadOnly="True" VerticalAlignment="Bottom" HorizontalScrollBarVisibility="Auto" VerticalScrollBarVisibility="Auto" Height="75" Margin="10,10,10,32"/>
        <Button Name="Btn_Start" HorizontalAlignment="Right" VerticalAlignment="Bottom" Width="75" Height="22" Content="Start" Margin="5,5,10,5"/>
        <Label Content="Computer List (Single Only)" HorizontalAlignment="Left" Width="170" VerticalAlignment="Top" Margin="10,249,0,0" VerticalContentAlignment="Center" HorizontalContentAlignment="Center"/>
        <TextBox Name="Txt_CompList" TextWrapping="Wrap" AcceptsReturn="True" HorizontalAlignment="Left" Text="" Width="170" Margin="10,275,0,122" HorizontalScrollBarVisibility="Auto" VerticalScrollBarVisibility="Auto"/>
    </Grid>
</Window>
'@

$XMLReader = (New-Object System.Xml.XmlNodeReader $xaml)
$SyncTable.Window = [Windows.Markup.XamlReader]::Load($XMLReader)
$SyncTable.Window.Add_Closed({$SyncTable.Host.Runspace.Events.GenerateEvent('On_Close', $SyncTable.Window, $null, '')})
$SyncTable.MS_File = $SyncTable.Window.FindName('MS_File')
$SyncTable.MS_File.Add_Click({$SyncTable.Host.Runspace.Events.GenerateEvent('MS_File_Click', $SyncTable.MS_File, $null, '')})
$SyncTable.MS_Exit = $SyncTable.Window.FindName('MS_Exit')
$SyncTable.MS_Exit.Add_Click({$SyncTable.Host.Runspace.Events.GenerateEvent('MS_Exit_Click', $SyncTable.MS_Exit, $null, '')})
$SyncTable.MS_Help = $SyncTable.Window.FindName('MS_Help')
$SyncTable.MS_Help.Add_Click({$SyncTable.Host.Runspace.Events.GenerateEvent('MS_Help_Click', $SyncTable.MS_Help, $null, '')})
$SyncTable.MS_About = $SyncTable.Window.FindName('MS_About')
$SyncTable.MS_About.Add_Click({$SyncTable.Host.Runspace.Events.GenerateEvent('MS_About_Click', $SyncTable.MS_About, $null, '')})
$SyncTable.Lbl_ColName = $SyncTable.Window.FindName('Lbl_ColName')
$SyncTable.Txt_UserList = $SyncTable.Window.FindName('Txt_UserList')
$SyncTable.Txt_CompList = $SyncTable.Window.FindName('Txt_CompList')
$SyncTable.Grid_Results = $SyncTable.Window.FindName('Grid_Results')
$SyncTable.Txt_Log = $SyncTable.Window.FindName('Txt_Log')
$SyncTable.Btn_Start = $SyncTable.Window.FindName('Btn_Start')
$SyncTable.Btn_Start.Add_Click({$SyncTable.UserList = $SyncTable.Txt_UserList.Text;$SyncTable.Host.Runspace.Events.GenerateEvent('Btn_Start_Click', $SyncTable.Btn_Start, $null, '')})
$Directory = $SyncTable.Directory
#$SyncTable.Window.Icon = "$Directory\NowMicroPointer.ico"
$SyncTable.Lbl_ColName.Content = 'Add Users to Group' + $SyncTable.ColName

$Timer = New-Object System.Windows.Threading.DispatcherTimer
$Timer.Interval = [TimeSpan]'0:0:1.00'

$Action = {
	$OldText = $SyncTable.Txt_Log.Text
	if ($OldText -ne $SyncTable.LogText) {
		$SyncTable.Txt_Log.Text = $SyncTable.LogText
		$SyncTable.Txt_Log.ScrollToEnd()
	}
	$Synctable.Grid_Results.ItemsSource = $Synctable.DataGridResults
}

$Timer.Add_Tick($Action)
$Timer.Start()

$SyncTable.Window.ShowDialog() | Out-Null
})
$psScript.Runspace = $Runspace
$Handle = $psScript.BeginInvoke()

Register-EngineEvent -SourceIdentifier 'On_Close' -Action {On_Close}
Register-EngineEvent -SourceIdentifier 'MS_Config_Click' -Action {MS_Config_Click}
Register-EngineEvent -SourceIdentifier 'MS_Exit_Click' -Action {MS_Exit_Click}
Register-EngineEvent -SourceIdentifier 'MS_About_Click' -Action {MS_About_Click}
Register-EngineEvent -SourceIdentifier 'Btn_Start_Click' -Action {Btn_Start_Click}

Start-Sleep 2

$SyncTable.Window.Dispatcher.Invoke(
	[Action]{
		$SyncTable.Window.ShowInTaskbar = $true
		},
	'Normal'
)

Pause-Script

