#requires -Version 3 -Modules ActiveDirectory
<#
    .Synopsis
    Add User to Specified Active Directory Group
   
    .DESCRIPTION
    This script will prompt for an individual User ID or take a Text file of User ID's.  With `
    the input it is possible to take the following actions agains a specified AD group.

    Add - Adds the User to the group.
    Verify - Verifys if the user is in the group or not with output.
    Remove - Removed the user from the group.
   
    .EXAMPLE

    .INPUTS

    .OUTPUTS

    .NOTES
    
    Requires: Powershell 3.0
    Active-Directory Module

    Author          : Chris Macnichol
    Version         : 0.6
    Version History : 
    0.6 - 02-05-2017 - No Result yet.
    0.5 - 02/02/2017 - Added Verify Action to GUI.  Basic Implementation.
    0.4 - Change Script Configuration from hard coded to a settings.ini file.  Added Auto `
    Generation of Settings.ini and User-Template.csv files.
    0.3 - Cleaned Script.
    0.2 - Add-Remove Functionality works.  Added ability to specify group name in CSV.
    0.1 - Initial Script With Add Group and Logging Functionality.  GUI Working.
    Created         : 01/23/2017
    Last updated    : 02/02/2017
#>


[CmdletBinding(DefaultParameterSetName = 'Parameter Set 1',
    SupportsShouldProcess = $true, 
    PositionalBinding = $false,
ConfirmImpact = 'Medium')]
[Alias()]
[OutputType([String])]
Param
(
  # Param1 help description
  [Parameter(Mandatory = $false, 
      ValueFromPipeline = $true,
      ValueFromPipelineByPropertyName = $true,
      Position = 0,
  ParameterSetName = 'Parameter Set 1')]
  [Alias('UserList')]
  $UserFile = $null
)

#region mainscript

Begin
{

  #region functions
  
  #Log File Function
  function Write-Log {
    <#
        .Synopsis 
        Write-Log writes a message to a specified log file with the current time stamp. 
        .DESCRIPTION 
        The Write-Log function is designed to add logging capability to other scripts. 
        In addition to writing output and/or verbose you can write to a log file for 
        later debugging. 
        .NOTES 
        Created by: Jason Wasser @wasserja 
        Modified: 11/24/2015 09:30:19 AM   
 
        Changelog: 
        * Code simplification and clarification - thanks to @juneb_get_help 
        * Added documentation. 
        * Renamed LogPath parameter to Path to keep it standard - thanks to @JeffHicks 
        * Revised the Force switch to work as it should - thanks to @JeffHicks 
 
        To Do: 
        * Add error handling if trying to create a log file in a inaccessible location. 
        * Add ability to write $Message to $Verbose or $Error pipelines to eliminate 
        duplicates. 
        .PARAMETER Message 
        Message is the content that you wish to add to the log file.  
        .PARAMETER Path 
        The path to the log file to which you would like to write. By default the function will  
        create the path and file if it does not exist.  
        .PARAMETER Level 
        Specify the criticality of the log information being written to the log (i.e. Error, Warning, Informational) 
        .PARAMETER NoClobber 
        Use NoClobber if you do not wish to overwrite an existing file. 
        .EXAMPLE 
        Write-Log -Message 'Log message'  
        Writes the message to c:\Logs\PowerShellLog.log. 
        .EXAMPLE 
        Write-Log -Message 'Restarting Server.' -Path c:\Logs\Scriptoutput.log 
        Writes the content to the specified log file and creates the path and file specified.  
        .EXAMPLE 
        Write-Log -Message 'Folder does not exist.' -Path c:\Logs\Script.log -Level Error 
        Writes the message to the specified log file as an error message, and writes the message to the error pipeline. 
        .LINK 
        https://gallery.technet.microsoft.com/scriptcenter/Write-Log-PowerShell-999c32d0 
    #>
    
    [CmdletBinding()] 
    Param 
    ( 
      [Parameter(Mandatory = $true, 
      ValueFromPipelineByPropertyName = $true)] 
      [ValidateNotNullOrEmpty()] 
      [Alias('LogContent')] 
      [string]$Message, 
 
      [Parameter(Mandatory = $false)] 
      [Alias('Path')] 
      [string]$logpath = "$script:LogDir", 
         
      [Parameter(Mandatory = $false)] 
      [ValidateSet('Error','Warn','Info')] 
      [string]$Level = 'Info', 
         
      [Parameter(Mandatory = $false)] 
      [switch]$NoClobber 
    ) 
 
    Begin 
    { 
       
      # Set VerbosePreference to Continue so that verbose messages are displayed. 
      $VerbosePreference = 'Continue'
      $ConfirmPreference = 'None'
      $WhatIfPreference = $false
    } 
    Process 
    { 
         
      # If the file already exists and NoClobber was specified, do not write to the log. 
      if ((Test-Path -Path $logpath) -AND $NoClobber) 
      { 
        Write-Log -Message "Log file $logpath already exists, and you specified NoClobber. Either `
        delete the file or specify a different name." -Level Error
        Return 
      } 
 
      # If attempting to write to a log file in a folder/path that doesn't exist create the file 
      # including the path. 
      elseif (!(Test-Path -Path $logpath)) 
      { 
        Write-Verbose -Message "Creating $logpath." 
        $NewLogFile = New-Item -Path $logpath -Force -ItemType File 
      } 
 
      else 
      {
        # Nothing to see here yet. 
      } 
 
      # Format Date for our Log File 
      $FormattedDate = Get-Date -Format 'yyyy-MM-dd HH:mm:ss' 
 
      # Write message to error, warning, or verbose pipeline and specify $LevelText 
      switch ($Level) { 
        'Error' 
        { 
          Write-Error -Message $Message 
          $LevelText = 'ERROR:' 
        } 
        'Warn' 
        { 
          Write-Warning -Message $Message 
          $LevelText = 'WARNING:' 
        } 
        'Info' 
        { 
          Write-Verbose -Message $Message 
          $LevelText = 'INFO:' 
        } 
      } 
         
      # Write log entry to $logpath 
      "$FormattedDate $LevelText $Message" | Out-File -FilePath $logpath -Append 
    } 
    End 
    { 
    } 
  }

  # Add User to AD Group
  function Add-UserToGroup {
    param
    (
      [String]
      $User = $null,
      
      [String]
      $adGroup = $null,
      
      [string]
      $Action = 'Add'
      
    )
      
    #region inputcheck
    if ($User -eq $null) 
    {
      Write-Log -Message 'User Input Empty, Skipping' -Level Warn;Return
    }

    # Set AD Group to default for action if not specified
    if (!($adGroup)) 
    {
      $adGroup = $Script:ADGroupI
      Write-Log -Message "No Active Directory Group Specified, Using default from Settings.ini: $adGroup" -Level Info
    }

    $group = Get-ADGroup -Identity $adGroup -Server $hbiServer
    
    #Getting user Details
    try 
    {
      $UserObj = Get-ADUser -Server $hbiServer -Identity $User -ErrorAction Stop
    }
    catch
    {
      Write-Log -Message "Error Getting User Details for: $User.  Skipping User" -Level Error
      return
    }
    #endregion inputcheck
      
      
    $SamAccount = $userObj.Name
    $groupName = $group.name

    Write-Log -Message "Checking if $($UserObj.name) is a member of $adGroup"
    
    $isMember = $(Get-ADUser -Server $hbiServer -Identity $userObj -Properties `
      MemberOf | Select-Object MemberOf -ExpandProperty MemberOf | Where-Object `
    {$_ -eq $Group.DistinguishedName} | Measure-Object | Select-Object -Expand Count)


    Switch ($Action) {

      Add {
    
        # Add User to Group
        Try 
        {
          if ($pscmdlet.ShouldProcess("$($group.name)", 'Adding User to Group'))
          {

            if ($isMember -eq '0') {
              Write-Log -Message "User is not a member of $($group.name), Adding User"
              Add-ADGroupMember -Identity $Group -Members $UserObj -Server $hbiServer -ErrorVariable addGrError -ErrorAction Stop   
              Write-Log -Message 'User Added Successfully'
              $result = 'Add'
            }
            else {
              Write-Log -Message "$($UserObj.SamAccountName) is already a member of Group: $($group.name), `
              Skipping Action" -Level Warn
              $result = 'Already a Member'
            }
          }
        }
        catch
        {
          Write-Log -Message "Unable to Add $($UserObj.name) to $($group.name)" -Level Error
          Write-Log -Message $addGrError -Level Error
        }
    
      }

      Remove {
    
        # Remove User from Group
        Try 
        {
          if ($pscmdlet.ShouldProcess("$($group.name)", 'Removing User from Group'))
          {
            if ($isMember -eq '0') {
              Write-Log -Message "$($UserObj.SamAccountName) is NOT a member of Group: $($group.name), `
              Skipping Action" -Level Warn
              $result = 'No Member to Remove'
              
            }
            else{
              Write-Log -Message "Found User in Group $($group.name), Removing User"
              Remove-ADGroupMember -Identity $Group -Members $UserObj -Server $hbiServer -ErrorVariable remGrError -ErrorAction Stop -Confirm:$false
              Write-Log -Message 'User Removed Successfully'
              $result = 'Removed Member'
            
            } # End Else
          } #End Should Process IF
        }
        catch
        {
          Write-Log -Message "Unable to Remove $($UserObj.name) from $($group.name)" -Level Warn
          Write-Log -Message $remGrError -Level Error
        }

      }
      
      Verify {
        if ($isMember -eq '0'){
          Write-Log -Message "User is not a member of $($group.name)"
          #$groupMember = 'False'
          $result = 'User is not a Member'
        }
        elseif($isMember -gt '0'){
          Write-Log -Message "User exists in group: $($group.name)"
          #$groupMember = 'True'
          $result = 'User is a member of the group'
        }
      
      }
    
    }
    $member = @()
    # Create Array to Store results
    $member = [PSCustomObject]@{
      Member = $(If($isMember -eq '0'){'True'}else{'False'})
      Result = $result
    }#EndPSCustomObject
  
    Return $member
  } # End Fuction Add user to Group
  
  #Parse INI File
  function Get-IniContent {  
    <#  
        .Synopsis  
        Gets the content of an INI file  
          
        .Description  
        Gets the content of an INI file and returns it as a hashtable  
          
        .Notes  
        Author        : Oliver Lipkau <oliver@lipkau.net>  
        Blog        : http://oliver.lipkau.net/blog/  
        Source        : https://github.com/lipkau/PsIni 
        http://gallery.technet.microsoft.com/scriptcenter/ea40c1ef-c856-434b-b8fb-ebd7a76e8d91 
        Version        : 1.0 - 2010/03/12 - Initial release  
        1.1 - 2014/12/11 - Typo (Thx SLDR) 
        Typo (Thx Dave Stiff) 
          
        #Requires -Version 2.0  
          
        .Inputs  
        System.String  
          
        .Outputs  
        System.Collections.Hashtable  
          
        .Parameter FilePath  
        Specifies the path to the input file.  
          
        .Example  
        $FileContent = Get-IniContent "C:\myinifile.ini"  
        -----------  
        Description  
        Saves the content of the c:\myinifile.ini in a hashtable called $FileContent  
      
        .Example  
        $inifilepath | $FileContent = Get-IniContent  
        -----------  
        Description  
        Gets the content of the ini file passed through the pipe into a hashtable called $FileContent  
      
        .Example  
        C:\PS>$FileContent = Get-IniContent "c:\settings.ini"  
        C:\PS>$FileContent["Section"]["Key"]  
        -----------  
        Description  
        Returns the key "Key" of the section "Section" from the C:\settings.ini file  
          
        .Link  
        Out-IniFile  
    #>  
      
    [CmdletBinding()]  
    Param(  
      [ValidateNotNullOrEmpty()]  
      [ValidateScript({(Test-Path $_) -and ((Get-Item $_).Extension -eq ".ini")})]  
      [Parameter(ValueFromPipeline=$True,Mandatory=$True)]  
      [string]$FilePath  
    )  
      
    Begin  
    {Write-Verbose "$($MyInvocation.MyCommand.Name):: Function started"}  
          
    Process  
    {  
      Write-Verbose "$($MyInvocation.MyCommand.Name):: Processing file: $Filepath"  
              
      $ini = @{}  
      switch -regex -file $FilePath  
      {  
        "^\[(.+)\]$" # Section  
        {  
          $section = $matches[1]  
          $ini[$section] = @{}  
          $CommentCount = 0  
        }  
        "^(;.*)$" # Comment  
        {  
          if (!($section))  
          {  
            $section = "No-Section"  
            $ini[$section] = @{}  
          }  
          $value = $matches[1]  
          $CommentCount = $CommentCount + 1  
          $name = "Comment" + $CommentCount  
          $ini[$section][$name] = $value  
        }   
        "(.+?)\s*=\s*(.*)" # Key  
        {  
          if (!($section))  
          {  
            $section = "No-Section"  
            $ini[$section] = @{}  
          }  
          $name,$value = $matches[1..2]  
          $ini[$section][$name] = $value  
        }  
      }  
      Write-Verbose "$($MyInvocation.MyCommand.Name):: Finished Processing file: $FilePath"  
      Return $ini  
    }  
          
    End  
    {Write-Verbose "$($MyInvocation.MyCommand.Name):: Function ended"}  
  } 
  
  #Export Replacement INI
  function Out-IniFile {  
    <#  
        .Synopsis  
        Write hash content to INI file  
            
        .Description  
        Write hash content to INI file  
            
        .Notes  
        Author        : Oliver Lipkau <oliver@lipkau.net>  
        Blog        : http://oliver.lipkau.net/blog/  
        Source        : https://github.com/lipkau/PsIni 
        http://gallery.technet.microsoft.com/scriptcenter/ea40c1ef-c856-434b-b8fb-ebd7a76e8d91 
        Version        : 1.0 - 2010/03/12 - Initial release  
        1.1 - 2012/04/19 - Bugfix/Added example to help (Thx Ingmar Verheij)  
        1.2 - 2014/12/11 - Improved handling for missing output file (Thx SLDR) 
            
        #Requires -Version 2.0  
            
        .Inputs  
        System.String  
        System.Collections.Hashtable  
            
        .Outputs  
        System.IO.FileSystemInfo  
            
        .Parameter Append  
        Adds the output to the end of an existing file, instead of replacing the file contents.  
            
        .Parameter InputObject  
        Specifies the Hashtable to be written to the file. Enter a variable that contains the objects or type a command or expression that gets the objects.  
    
        .Parameter FilePath  
        Specifies the path to the output file.  
         
        .Parameter Encoding  
        Specifies the type of character encoding used in the file. Valid values are "Unicode", "UTF7",  
        "UTF8", "UTF32", "ASCII", "BigEndianUnicode", "Default", and "OEM". "Unicode" is the default.  
            
        "Default" uses the encoding of the system's current ANSI code page.   
            
        "OEM" uses the current original equipment manufacturer code page identifier for the operating   
        system.  
         
        .Parameter Force  
        Allows the cmdlet to overwrite an existing read-only file. Even using the Force parameter, the cmdlet cannot override security restrictions.  
            
        .Parameter PassThru  
        Passes an object representing the location to the pipeline. By default, this cmdlet does not generate any output.  
                    
        .Example  
        Out-IniFile $IniVar "C:\myinifile.ini"  
        -----------  
        Description  
        Saves the content of the $IniVar Hashtable to the INI File c:\myinifile.ini  
            
        .Example  
        $IniVar | Out-IniFile "C:\myinifile.ini" -Force  
        -----------  
        Description  
        Saves the content of the $IniVar Hashtable to the INI File c:\myinifile.ini and overwrites the file if it is already present  
            
        .Example  
        $file = Out-IniFile $IniVar "C:\myinifile.ini" -PassThru  
        -----------  
        Description  
        Saves the content of the $IniVar Hashtable to the INI File c:\myinifile.ini and saves the file into $file  
    
        .Example  
        $Category1 = @{"Key1"="Value1";"Key2"="Value2"}  
        $Category2 = @{"Key1"="Value1";"Key2"="Value2"}  
        $NewINIContent = @{"Category1"=$Category1;"Category2"=$Category2}  
        Out-IniFile -InputObject $NewINIContent -FilePath "C:\MyNewFile.INI"  
        -----------  
        Description  
        Creating a custom Hashtable and saving it to C:\MyNewFile.INI  
        .Link  
        Get-IniContent  
    #>  
        
    [CmdletBinding()]  
    Param(  
      [switch]$Append,  
            
      [ValidateSet("Unicode","UTF7","UTF8","UTF32","ASCII","BigEndianUnicode","Default","OEM")]  
      [Parameter()]  
      [string]$Encoding = "Unicode",  
   
            
      [ValidateNotNullOrEmpty()]  
      [ValidatePattern('^([a-zA-Z]\:)?.+\.ini$')]  
      [Parameter(Mandatory=$True)]  
      [string]$FilePath,  
            
      [switch]$Force,  
            
      [ValidateNotNullOrEmpty()]  
      [Parameter(ValueFromPipeline=$True,Mandatory=$True)]  
      [Hashtable]$InputObject,  
            
      [switch]$Passthru  
    )  
        
    Begin  
    {Write-Verbose "$($MyInvocation.MyCommand.Name):: Function started"}  
            
    Process  
    {  
      Write-Verbose "$($MyInvocation.MyCommand.Name):: Writing to file: $Filepath"  
            
      if ($append) {$outfile = Get-Item $FilePath}  
      else {$outFile = New-Item -ItemType file -Path $Filepath -Force:$Force}  
      if (!($outFile)) {Throw "Could not create File"}  
      foreach ($i in $InputObject.keys)  
      {  
        if (!($($InputObject[$i].GetType().Name) -eq "Hashtable"))  
        {  
          #No Sections  
          Write-Verbose "$($MyInvocation.MyCommand.Name):: Writing key: $i"  
          Add-Content -Path $outFile -Value "$i=$($InputObject[$i])" -Encoding $Encoding  
        } else {  
          #Sections  
          Write-Verbose "$($MyInvocation.MyCommand.Name):: Writing Section: [$i]"  
          Add-Content -Path $outFile -Value "[$i]" -Encoding $Encoding  
          Foreach ($j in $($InputObject[$i].keys | Sort-Object))  
          {  
            if ($j -match "^Comment[\d]+") {  
              Write-Verbose "$($MyInvocation.MyCommand.Name):: Writing comment: $j"  
              Add-Content -Path $outFile -Value "$($InputObject[$i][$j])" -Encoding $Encoding  
            } else {  
              Write-Verbose "$($MyInvocation.MyCommand.Name):: Writing key: $j"  
              Add-Content -Path $outFile -Value "$j=$($InputObject[$i][$j])" -Encoding $Encoding  
            }  
                        
          }  
          Add-Content -Path $outFile -Value "" -Encoding $Encoding  
        }  
      }  
      Write-Verbose "$($MyInvocation.MyCommand.Name):: Finished Writing to file: $path"  
      if ($PassThru) {Return $outFile}  
    }  
            
    End  
    {Write-Verbose "$($MyInvocation.MyCommand.Name):: Function ended"}  
  } 
  
  function Create-SettingsFile {
  
    $GeneralSettings = @{"Domain`t`t`t"="`thbiusers.hbicorp.huntington.com"}
    $UserSettings = @{"DefaultGroup`t`t"="`tI_CreativeCloud_DG";"DefaultUserFileName`t"="`tUsers"}
    [hashtable]$NewINI = @{"GeneralSettings"=$GeneralSettings;"UserSettings"=$UserSettings}
    
    Write-Log -Message 'Creating Settings File from Hard Coded Defaults.' -Level Warn
    try {
      Out-IniFile -FilePath "$PSScriptRoot\Settings.ini" -InputObject $NewINI -ErrorAction Stop -Force
    }
    catch {
      Write-Log -Message 'Something went wrong creating the file, Pelase contact support.' -Level Error
      Exit-PSHostProcess
    }
    
  }
  
  #region XAML window definition
  # Right-click XAML and choose WPF/Edit... to edit WPF Design
  # in your favorite WPF editing tool
  $xaml = @'
<Window
   xmlns="http://schemas.microsoft.com/winfx/2006/xaml/presentation"
   xmlns:x="http://schemas.microsoft.com/winfx/2006/xaml"
   MinWidth="400"
   Width ="400.00"
   SizeToContent="Height"
   Title="User Group Management"
   Topmost="True" Height="275.0" WindowStartupLocation="CenterScreen" MaxWidth="400" MaxHeight="250" MinHeight="250">
    <Grid Margin="10,10,10.333,2.333">
        <Grid.ColumnDefinitions>
            <ColumnDefinition Width="Auto"/>
            <ColumnDefinition Width="*"/>
        </Grid.ColumnDefinitions>
        <Grid.RowDefinitions>


            <RowDefinition Height="61*"/>
            <RowDefinition Height="118*"/>
            <RowDefinition Height="54*"/>
        </Grid.RowDefinitions>

        <StackPanel Orientation="Horizontal" HorizontalAlignment="Right" VerticalAlignment="Bottom" Margin="0,0,9.333,12.333" Grid.Column="1" Height="32" Width="180" Grid.Row="2">
            <Button x:Name="ButOk" MinWidth="80" Height="22" Margin="5" Content="Add"/>
            <Button x:Name="ButCancel" MinWidth="80" Height="22" Margin="5" Content="Close"/>
        </StackPanel>
        <Label x:Name="Group_Label" Content="Identity Group:" HorizontalAlignment="Center" VerticalAlignment="Top" Height="30" AutomationProperties.IsColumnHeader="True" Width="100" FontWeight="Bold" Margin="1,4.333,16.333,0" Grid.Row="1"/>
        <Label x:Name="UserID_Label" Content="User ID:" HorizontalAlignment="Center" VerticalAlignment="Top" Height="30" AutomationProperties.IsColumnHeader="True" Width="100" Margin="1,39.333,16.333,0" FontWeight="Bold" Grid.Row="1"/>
        <TextBox x:Name="IdentityGroup" HorizontalAlignment="Left" Height="24" Margin="9.667,4.333,0,0" TextWrapping="Wrap" VerticalAlignment="Top" MinWidth="244" AutomationProperties.HelpText="Example: I_GroupName_DG" ToolTip="Example: I_GroupName_DG" Grid.Row="1" Grid.Column="1"/>
        <TextBox x:Name="User_ID" HorizontalAlignment="Left" Height="24" Margin="9.667,39.333,0,0" TextWrapping="Wrap" VerticalAlignment="Top" MinWidth="244" AutomationProperties.HelpText="Example: HBxxxxx" ToolTip="Example: HBxxxxx" Grid.Row="1" Grid.Column="1"/>
        <Label x:Name="AddRemove_User_Text" Content="Add\Remove User:" HorizontalAlignment="Left" VerticalAlignment="Top" Margin="1,14,0,0" FontWeight="Bold" Height="28"/>
        <StackPanel Orientation="Horizontal" HorizontalAlignment="Left" VerticalAlignment="Top" Margin="1,14,0,0" Height="28" Width="230" Grid.Column="1">
            <RadioButton IsChecked="True" x:Name="Add" Content="Add" MinWidth="60" Height="22" Margin="5" GroupName="Action" AutomationProperties.HelpText="Chose to Add the User to the Specified Group" ToolTip="Chose to Add the User to the Specified Group" HorizontalAlignment="Left" VerticalAlignment="Top"/>
            <RadioButton x:Name="Verify" Content="Verify" MinWidth="60" Height="22" Margin="5,5,5,0" GroupName="Action" AutomationProperties.HelpText="Chose to Verify if the User is in the Specified Group" ToolTip="Chose to Verify if the User is in the Specified Group" HorizontalAlignment="Left" VerticalAlignment="Top"/>
            <RadioButton x:Name="Remove" Content="Remove" MinWidth="60" Height="22" Margin="5" GroupName="Action" AutomationProperties.HelpText="Chose to Remove the User from the Specified Group" ToolTip="Chose to Remove the User from the Specified Group" HorizontalAlignment="Left" VerticalAlignment="Top"/>
        </StackPanel>

    </Grid>
</Window>
'@
  #endregion

  #region Code Behind
  function Convert-XAMLtoWindow
  {
    param
    (
      [Parameter(Mandatory)]
      [string]
      $XAML,
    
      [string[]]
      $NamedElement=$null,
    
      [switch]
      $PassThru
    )
  
    Add-Type -AssemblyName PresentationFramework
  
    $reader = [XML.XMLReader]::Create([IO.StringReader]$XAML)
    $result = [Windows.Markup.XAMLReader]::Load($reader)
    foreach($Name in $NamedElement)
    {
      $result | Add-Member NoteProperty -Name $Name -Value $result.FindName($Name) -Force
    }
  
    if ($PassThru)
    {
      $result
    }
    else
    {
      $null = $window.Dispatcher.InvokeAsync{
        $result = $window.ShowDialog()
        Set-Variable -Name result -Value $result -Scope 1
      }.Wait()
      $result
    }
  }

  function Show-WPFWindow
  {
    param
    (
      [Parameter(Mandatory)]
      [Windows.Window]
      $Window
    )
  
    $result = $null
    $null = $window.Dispatcher.InvokeAsync{
      $result = $window.ShowDialog()
      Set-Variable -Name result -Value $result -Scope 1
    }.Wait()
    $result
  }
  #endregion Code Behind
  
  #endregion functions

  <#bookmark HardCodedSettings#>
  ##Hard Coded Settings##
  #Log File Name
  [string]$logdir = "$PSScriptRoot\AddRemove-UserAdGroup.log"
  #Settings File Location\Name
  [String]$SettingsFile = "$PSScriptRoot\Settings.ini"
  $users = $null
  
  #Script Start
  Write-Log -Message '--------------------------------------------'
  Write-Log -Message "Beginning $($MyInvocation.InvocationName) on `
  $($env:COMPUTERNAME) by $env:USERDOMAIN\$env:USERNAME" -Level Info
  Write-Log -Message "Script is running from: $PSScriptRoot"
  Write-Log -Message "Log File: $logdir"
  Write-Log -Message '--------------------------------------------'
  
  #region importsettings
  #Importing Settings from INI File
  Write-Log -Message 'Checking for Settings File'
  
  if (!(Test-Path -Path $SettingsFile)) {
    Write-Log -Message 'Settings file does not exist.' -Level Error
    Create-SettingsFile
  }
  else
  {
    try {
      $settings = Get-IniContent -FilePath $SettingsFile -ErrorAction Stop -ErrorVariable importini
      Write-Log -Message 'Settings File Successfully Imported'
    }
    catch
    {
      Write-Log -Message "Something went wrong Importing the Settings File: $importini" -Level Error
      Create-SettingsFile
    }
  }
  
  if ($settings -eq $null) {
  
    try {
      $settings = Get-IniContent -FilePath $SettingsFile -ErrorAction Stop -ErrorVariable importini
      Write-Log -Message 'Default Settings File Successfully Imported'
    }
    catch
    {
      Write-Log -Message "Something went wrong Importing the Default Settings File. `
      Please contact Support.  Exiting.  $importini" -Level Error
      Exit

    }
      
  }
  #endregion
  
  #region settings
  
  ##Setting Values from Setting File
  #User File Name
  if ($UserFile -eq $null) {
    [string]$UserFile = "$PSScriptRoot\$($Settings.UserSettings.DefaultUserFileName).csv"
  }
  
  # AD Group to Add or Remove Users From
  $Script:ADGroupI = $($Settings.UserSettings.DefaultGroup)
  
  # Server Address
  $hbiServer = $($Settings.GeneralSettings.Domain)

  #endregion

  #region checkuserfile
  Write-Log -Message "Checking for User File: $UserFile"
  
  #Import User File if it Exists
  if ($(Test-Path -Path $UserFile)) {
  
    $userFilePath = $UserFile
    
    Write-Log -Message "Found User File at: $userFilePath"
         
    [System.Reflection.Assembly]::LoadWithPartialName('Microsoft.VisualBasic')
    $choice = [Microsoft.VisualBasic.Interaction]::MsgBox("Would you like to use the user file located at: `n $userFilePath",'YesNoCancel,Question', 'Respond please')
    
    if ($choice -eq 'Yes') 
    {
      $users = Import-Csv -Path $UserFile
      Write-Log -Message 'Importing User File' -Level Info
    }
    elseif ($choice -eq 'No') 
    {
      Write-Log -Message 'Declined to Import User File' -Level Info
      $users = $null #Clear Variable for Testing
    }
    
  } #end Test Path
  else{
  
    Write-Log -Message "No user file found with name: $($Settings.UserSettings.DefaultUserFileName).csv" -Level Info
    
    if (!(Test-Path $PSScriptRoot\Users-Template.csv)) {
      # Create Array to Store results
      $headers = [PSCustomObject]@{
        Action = 'Verify'
        User = 'HBxxxxx'
        Domain = 'Domain(NotRequired)'
        Group = 'Identity Group(NotRequired)'
      }#EndPSCustomObject
      Write-Log -Message "Creating Template CSV File (Users-Template.csv). For bulk actions please `
      alter this file and rename it to match the User File name in the settings.ini file." -Level Warn
      Export-Csv -Path $PSScriptRoot\Users-Template.csv -Force -NoTypeInformation -InputObject $headers
      "Add,HBID,Domain(NotRequired),Identity Group(NotRequired)" | Out-File -FilePath $PSScriptRoot\Users-Template.csv -Append
      "Remove,HBID,Domain(NotRequired),Identity Group(NotRequired)" | Out-File -FilePath $PSScriptRoot\Users-Template.csv -Append
    }
  }
  #endregion checkuserfile


  #Check For User Content
  if (!($users)) 
  {
    Write-Log -Message 'Requesting Input'
    
    #Define Window from XAML
    #region Convert XAML to Window
    $window = Convert-XAMLtoWindow -XAML $xaml -NamedElement 'Add', 'AddRemove_User_Text', 'ButCancel', 'ButOk', 'Group_Label', 'IdentityGroup', 'Remove', 'User_ID', 'UserID_Label', 'Verify' -PassThru
    
    #endregion Convert XAML to Window
    
    # Call the GUI function
    #LEGACY $users = Input-Form

    <#Bookmark Event Handlers#>
    #region Define Event Handlers
    # Right-Click XAML Text and choose WPF/Attach Events to
    # add more handlers
    $window.ButCancel.add_Click(
      {
        $window.DialogResult = $false
      }
    )
    $window.Add.add_Checked{
      # remove param() block if access to event information is not required
      param
      (
        [Parameter(Mandatory)][Object]$sender,
        [Parameter(Mandatory)][Windows.RoutedEventArgs]$e
      )
  
      $script:guiAction = 'Add'
      $window.ButOk.Content = 'Add'
    }
    $window.Verify.add_Checked{
      # remove param() block if access to event information is not required
      param
      (
        [Parameter(Mandatory)][Object]$sender,
        [Parameter(Mandatory)][Windows.RoutedEventArgs]$e
      )
  
      $script:guiAction = 'Verify'
      $window.ButOk.Content = 'Verify'
    }
    $window.Remove.add_Checked{
      # remove param() block if access to event information is not required
      param
      (
        [Parameter(Mandatory)][Object]$sender,
        [Parameter(Mandatory)][Windows.RoutedEventArgs]$e
      )
  
      $script:guiAction = 'Remove'
      $window.ButOk.Content = 'Remove'
    }

    $window.add_KeyDown{
      param
      (
        [Parameter(Mandatory)][Object]$sender,
        [Parameter(Mandatory)][Windows.Input.KeyEventArgs]$e
      )
      if($e.Key -eq 'Enter')
      {
        $guiResult = Add-UserToGroup -User $window.User_ID.Text -adGroup $window.IdentityGroup.Text -Action $script:guiAction
        [System.Windows.MessageBox]::Show("Action '$($script:guiAction)' completed against User $($window.User_ID.Text) for group $($window.IdentityGroup.Text) with result: $($guiResult.Result)",'Result')
      }

      $window.ButOk.add_Click(
        {

        $guiResult = Add-UserToGroup -User $window.User_ID.Text -adGroup $window.IdentityGroup.Text -Action $script:guiAction
        #[System.Windows.MessageBox]::Show("Action '$($script:guiAction)' completed against User $($window.User_ID.Text) for group $($window.IdentityGroup.Text) with result: $($guiResult.Result)",'Result')
        
        }
      )

      if($e.Key -eq 'Escape')
      {
        $window.DialogResult = $false
      }    
    }

    #endregion Event Handlers

    #region Manipulate Window Content
    
    $clip = Get-Clipboard
    if ($clip -eq $null -or $clip -eq '') {$clip = ''} 
    else {
      $clip = $clip.ToLower()
    }
    
    if ($clip.StartsWith('hb') -or $clip.StartsWith('zz') ){
      $window.User_ID.Text = $clip
      $null = $window.User_ID.Focus()
      $null = $window.User_ID.SelectAll()
    }
    else {
      $null = $window.User_ID.Focus()
      $window.User_ID.Text = $null
    }
    
    #PreFills Group Field with Settings File Group
    $window.IdentityGroup.Text = $Script:ADGroupI
    #endregion
    
    # Show Window - Call GUI
    $result = Show-WPFWindow -Window $window
    
    #region Process results
    if ($result -eq $true)
    {
      $users = [Ordered]@{
        Group = $window.IdentityGroup.Text
        User = $window.User_ID.Text
        Action = $script:guiACtion
      }
      New-Object -TypeName PSObject -Property $users | out-null
      
      Write-Log -Message "$($users.User) with Action: $script:guiaction, received from GUI"
    }
    else
    {
      Write-Log -Message "Script Canceled, No Input Received" -Level Warn
    }
    #endregion Process results
    
    
  }

}

Process
{

  if ($users -ne $null) {
  
    $verifyResults = @()
    
    foreach ($item in $users)
    {
      $adGroup = $null

      Write-Log -Message '--------------------------------------------'
      Write-Log -Message "Processing Action $($item.Action) for User $($item.User)" -Level Info
    
      if ($item.group -match '([A-Z_])' -and $item.group -ne $null -and $item.group -ne '') `
      {$adGroup = $item.group}

      Add-UserToGroup -User $item.User -adGroup $adGroup -Action $item.Action
    }
  }
}
End
{
  
  Write-Log -Message '--------------------------------------------'
  Write-Log -Message 'Finished'
  Write-Log -Message '--------------------------------------------'
}

#endregion