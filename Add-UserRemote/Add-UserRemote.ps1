$ComputerList = Get-content .\ComputerList.txt

Foreach($Workstation in $ComputerList){
$domainuser = "HBIUSERS\userORgroup"
$localgroup = "localgroup"

Write-Host "$Workstation adding $domainuser to $localgroup"
$objUser = [ADSI]("WinNT://$domainuser") 
$objGroup = [ADSI]("WinNT://$Workstation/$localgroup") 
$objGroup.PSBase.Invoke("Add",$objUser.PSBase.Path)


}

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
$_.GetType().InvokeMember("Name",  'GetProperty',  $null,  $_, $null)
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
Write-Verbose  "Scanning all groups"
$groups = $adsi.Children | where {$_.SchemaClassName -eq 'group'}
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
Throw "No groups found!"
}
} Catch {
Write-Warning  "$($Computer): $_"
}
}
}
}

#Get-LocalGroup -Computername $env:COMPUTERNAME -Group 'Remote Desktop Users' -Verbose | Format-List

Function Btn_Start_Click {
Write-Verbose "Start-Click Begin"

if ($SyncTable.UserList -eq $null){[System.Windows.Forms.MessageBox]::Show("User List in Empty.  Please enter at least one User ID." , "Missing User ID" , 0) | Out-Null; Exit}

	$RulesToSkip = $null
	$strMessage = "Do you want to add these users to $colname" + "?"
	$PopupAnswer = $Popup.Popup($strMessage,0,"Are you sure?",1)

	if ($PopupAnswer -eq 1) {
		$UserNameArray = $SyncTable.UserList
		$UserNameArray = $UserNameArray.Split("`n")
		$UserNameArray = $UserNameArray.Split("`r")
		$UserNameArray = $UserNameArray | select -Unique
		
		Log -Message "Getting current user list for Computer: " + $comp

        $users = Get-LocalGroup -Computername $SyncTable.CompList -Group 'Remote Desktop Users'

		foreach ($user in $users.Members) {

				if ($UserNameArray -icontains $user) {$UsersToSkip += @($user)}
		}
		
        #Log -Message "Starting to add rules..."

		foreach ($UserName in $UserNameArray) {

			if ($UsersToSkip -contains $UserName) {
				Log -Message "$UserName already exists in Group!"
				$Results = Select-Object -InputObject "" Name, Result
				$Results.Name = $UserName
				$Results.Result = "User already exists"
				$Synctable.DataGridResults += $Results
			}
			elseif ($UserName -eq "") {}
			else {
				if ($UserName -ne $null) {

                    $domainuser = "HBIUSERS\" + $UserName
                    $localgroup = "Remote Desktop Users"

                    Log -Message "Adding $domainuser to $localgroup on $comp"

                    $objUser = [ADSI]("WinNT://$domainuser") 
                    $objGroup = [ADSI]("WinNT://$Workstation/$localgroup") 
                    $objGroup.PSBase.Invoke("Add",$objUser.PSBase.Path)

                            if ($Error[0]) {
								Log -Message "Error adding $Comp - $Error"
								$ErrorMessage = "$Error"
								$ErrorMessage = $ErrorMessage.Replace("`n","")
								$Results = Select-Object -InputObject "" Name, Result
								$Results.Name = $CompName
								$Results.Result = "$ErrorMessage"
								$Synctable.DataGridResults += $Results
							}
							else {
								Log -Message "Successfully added $UserName"
								$Results = Select-Object -InputObject "" Name, Result
								$Results.Name = $CompName
								$Results.Result = "Successfully Added"
								$Synctable.DataGridResults += $Results
							}
					}
					if ($ResourceID -eq $null) {
						Log -Message "Could not find $UserName - No rule added"
						$Results = Select-Object -InputObject "" Name, Result
						$Results.Name = $UserName
						$Results.Result = "No Resource ID"
						$Synctable.DataGridResults += $Results
					}
				}
			}
		#}
	}
	Log -Message "Finished!"
}


$Global:SyncTable = [HashTable]::Synchronized(@{})
$SyncTable.Host = $Host
$SyncTable.ColName = ": Remote Desktop Users" #$ColName
$SyncTable.Directory = $Directory
$Synctable.DataGridResults = New-Object System.Collections.Arraylist
$Runspace = [RunspaceFactory]::CreateRunspace()
$Runspace.ApartmentState = "STA"
$Runspace.ThreadOptions = "ReuseThread"
$Runspace.Open()
$Runspace.SessionStateProxy.SetVariable("SyncTable",$SyncTable)

$psScript = [Powershell]::Create().AddScript({

Add-Type -AssemblyName PresentationFramework,PresentationCore,WindowsBase

$XMLReader = (New-Object System.Xml.XmlNodeReader $xaml)
$SyncTable.Window = [Windows.Markup.XamlReader]::Load($XMLReader)

$SyncTable.Window.Add_Closed({$SyncTable.Host.Runspace.Events.GenerateEvent("On_Close", $SyncTable.Window, $null, "")})
$SyncTable.MS_File = $SyncTable.Window.FindName("MS_File")
$SyncTable.MS_File.Add_Click({$SyncTable.Host.Runspace.Events.GenerateEvent("MS_File_Click", $SyncTable.MS_File, $null, "")})
$SyncTable.MS_Exit = $SyncTable.Window.FindName("MS_Exit")
$SyncTable.MS_Exit.Add_Click({$SyncTable.Host.Runspace.Events.GenerateEvent("MS_Exit_Click", $SyncTable.MS_Exit, $null, "")})
$SyncTable.MS_Help = $SyncTable.Window.FindName("MS_Help")
$SyncTable.MS_Help.Add_Click({$SyncTable.Host.Runspace.Events.GenerateEvent("MS_Help_Click", $SyncTable.MS_Help, $null, "")})
$SyncTable.MS_About = $SyncTable.Window.FindName("MS_About")
$SyncTable.MS_About.Add_Click({$SyncTable.Host.Runspace.Events.GenerateEvent("MS_About_Click", $SyncTable.MS_About, $null, "")})
$SyncTable.Lbl_ColName = $SyncTable.Window.FindName("Lbl_ColName")
$SyncTable.Txt_UserList = $SyncTable.Window.FindName("Txt_UserList")
$SyncTable.Txt_CompList = $SyncTable.Window.FindName("Txt_CompList")
$SyncTable.Grid_Results = $SyncTable.Window.FindName("Grid_Results")
$SyncTable.Txt_Log = $SyncTable.Window.FindName("Txt_Log")
$SyncTable.Btn_Start = $SyncTable.Window.FindName("Btn_Start")
$SyncTable.Btn_Start.Add_Click({$SyncTable.UserList = $SyncTable.Txt_UserList.Text;$SyncTable.Host.Runspace.Events.GenerateEvent("Btn_Start_Click", $SyncTable.Btn_Start, $null, "")})
$Directory = $SyncTable.Directory
#$SyncTable.Window.Icon = "$Directory\NowMicroPointer.ico"
$SyncTable.Lbl_ColName.Content = "Add Users to Group" + $SyncTable.ColName

$Timer = New-Object System.Windows.Threading.DispatcherTimer
$Timer.Interval = [TimeSpan]"0:0:1.00"

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
