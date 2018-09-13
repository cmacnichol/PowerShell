<#
      .SYNOPSIS
      Get-ManagedByGroups

      .DESCRIPTION
      Script will retrieve a list of AD Groups where the ManagedBy Attribute is empty and output it to a CSV File.
      With the 'Set' Switch the script will process the csv and set the ManagedBy Value on the domain object.
      - 
      .INPUT
      ManagedByGroups.csv

      Set (Switch)
      InputPath (Path to Input File)
      OutputPath (Path to Output File)

      .OUTPUT
      ManagedByGroups.csv
      

      .EXAMPLE


      .NOTES
      - V0.2  Chris Macnichol (07/08/2016) Added Hbicorp Domain Search and Logging.  Variables need to be cleaned up still and more validation needs to be added.
      - V0.1  Chris Macnichol (07/07/2016) Base Script


#>

[cmdletbinding(DefaultParameterSetName=’OutputPath’)]
param(   
    [Parameter(ParameterSetName=’OutputPath’,
            Mandatory=$False,  
      Position=0)]
    [string[]]$OutputPath = 'C:\Temp\ManagedByGroups.csv',
         
    [Parameter(ParameterSetName=’Set’,
            Mandatory=$False,  
      Position=0)]
    [string[]]$InputPath = 'C:\Temp\ManagedByGroups.csv',

    [Parameter(ParameterSetName=’Set’,
            Mandatory=$True,
      Position=1)]
    [Switch]$Set = $false
) 

begin
{
    # Define Search Base
    $ou = 'DC=hbiusers,DC=hbicorp,DC=huntington,DC=com'
    # Define Domain Controller
    $DC = 'pdwadsusers03.hbiusers.hbicorp.huntington.com'
    
    [string]$logpath='C:\temp\PowerShellLog.log'
    
    function Write-Log  {
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
        [Parameter(Mandatory=$true, 
                   ValueFromPipelineByPropertyName=$true)] 
        [ValidateNotNullOrEmpty()] 
        [Alias('LogContent')] 
        [string]$Message, 
 
        [Parameter(Mandatory=$false)] 
        [Alias('Path')] 
        [string]$logpath='C:\temp\PowerShellLog.log', 
         
        [Parameter(Mandatory=$false)] 
        [ValidateSet('Error','Warn','Info')] 
        [string]$Level='Info', 
         
        [Parameter(Mandatory=$false)] 
        [switch]$NoClobber 
    ) 
 
    Begin 
    { 
       
        # Set VerbosePreference to Continue so that verbose messages are displayed. 
        $VerbosePreference = 'Continue'      
    } 
    Process 
    { 
         
        # If the file already exists and NoClobber was specified, do not write to the log. 
        if ((Test-Path $logpath) -AND $NoClobber) { 
            Write-Error "Log file $logpath already exists, and you specified NoClobber. Either delete the file or specify a different name." 
            Return 
            } 
 
        # If attempting to write to a log file in a folder/path that doesn't exist create the file including the path. 
        elseif (!(Test-Path $logpath)) { 
            Write-Verbose "Creating $logpath." 
            $NewLogFile = New-Item $logpath -Force -ItemType File 
            } 
 
        else { 
            # Nothing to see here yet. 
            } 
 
        # Format Date for our Log File 
        $FormattedDate = Get-Date -Format 'yyyy-MM-dd HH:mm:ss' 
 
        # Write message to error, warning, or verbose pipeline and specify $LevelText 
        switch ($Level) { 
            'Error' { 
                Write-Error $Message 
                $LevelText = 'ERROR:' 
                } 
            'Warn' { 
                Write-Warning $Message 
                $LevelText = 'WARNING:' 
                } 
            'Info' { 
                Write-Verbose $Message 
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
  
        Write-Log '--------------------------------------------'
        Write-Log "Beginning $($MyInvocation.InvocationName) on $($env:COMPUTERNAME) by $env:USERDOMAIN\$env:USERNAME" -Level Info
        function Get-EmptyManagedByGroups  {
        param
        (
            [String]
            $OutputPath
        )

        Write-Log -Message 'Retrieving List of AD Groups without a ManagedBy Entry from HBICORP'
        
        #Hbicorp Search
        $groupsResultHbicorp = @(Get-ADGroup -Server $DC -SearchBase $ou -LDAPFilter '(&(sAMAccountNAme=*Admin*)(objectClass=group)(!(managedBy=*)))' -Properties ManagedBy, Description)
        
        Write-Log -Message "Exporting HBICorp groups to $outputpath"
        #Hbicorp Export
        $groupsResultHbicorp | Select-Object Name, DistinguishedName, Description, SamAccountName, ManagedBy | Export-CSV -Path $OutputPath -NoTypeInformation
        Write-Log -Message "Found $($GroupsResulthbicorp.count) HBICORP Groups with Missing ManagedBy Entry"

        Write-Log -Message 'Retrieving List of AD Groups without a ManagedBy Entry from HBANC'        
        #Hbanc Search
        $groupsResultHbanc = Get-ADGroup -LDAPFilter '(&(sAMAccountNAme=*Admin*)(objectClass=group)(!(managedBy=*)))' -Properties ManagedBy
        Write-Log -Message "Found $($groupsResultHbanc.count) HBANC Groups with Missing ManagedBy Entry"
        
        Write-Log -Message "Appending HBANC groups to $outputpath"   
        #Hbanc Export
        $groupsResultHbanc | Select-Object Name, DistinguishedName, Description, SamAccountName, ManagedBy | Export-CSV -Path $OutputPath -NoTypeInformation -Append
        
        Write-Log -Message "A total of $($groupsResultHbanc.count + $groupsResultHbicorp.count) Groups have Missing ManagedBy Entries"
        
    }

    function Set-EmptyManagedByGroup  {
        param
        (
            [String]
            $InputPath
        )

        Write-Log -Message "Importing Group list from $InputPath"
        $ManagedGroups = Import-CSV -Path $InputPath
        Write-Log -Message "Imported $($ManagedGroups.count) Groups"

        $changedGroups = $managedgroups | Where-Object {$_.ManagedBy -ne ''} #Note, Add Validation of Input later.
        
        if (!($changedGroups)) {Write-Log -Message 'No Changes found within Input File'; Return} #Note, Add Comparison to Previously Pulled Results

        foreach ($item in $changedGroups) {
        
          Write-Log -Message "Processing Group $($item.Name)"
          
                $samAccountName = $item.ManagedBy
                
          Write-Log -Message "Processing Input ManagedBy Name $samAccountName"
          try {      
            $user = Get-ADUser -Server $dc -SearchBase $ou -Filter {(SamAccountName -eq $samAccountName)} -ErrorAction Stop | Select-Object -ExpandProperty DistinguishedName
              }
              catch{Write-Error -Message "Unable to Retrive User Object for $samAccountName, Skipping Entry"; Return} 
              
          Write-Log -Message "Found $user"
          
          $item = 'CN=RPAD_H_DV_dvwqrmdb07_RECON4_bulkadmin,OU=Groups,OU=IDM_Managed,DC=hbanc,DC=hban,DC=us'
          
          Write-Log -Message 'Checking if group has been updated since it was pulled'
          
          if($item.DistinguishedName -like '*hbanc*'){$check = (Get-ADGroup -Identity $item -Properties ManagedBy | Select-Object -ExpandProperty ManagedBy)} Else{$check = (Get-ADGroup -Server $DC -Identity $item -Properties ManagedBy | Select-Object -ExpandProperty ManagedBy)}          
          
          if (!($check -eq '' -or -$null) -and $check -ne $item.DistinguishedName) {
            Write-Warning -Message "Group $($Item.name) ManagedBy has changed."
            Write-Warning -Message "AD ManagedBys is $check"
            Write-Warning -Message "CSV Input is $item.DistinguishedName"
            Write-Warning -Message "Skipping $item.name"
            Return
          }
          
          Write-Log -Message "Setting ManagedBy Object for Group $($item.Name)"     
          try {
            Set-ADGroup -Server $DC -Identity $item.DistinguishedName -ManagedBy $user -WhatIf
              }
              catch{Write-Error -Message 'Unable to Set ManagedBY Property, Skipping Entry'; Return}
              
          Write-Log -Message "Successfully Set ManagedBy Property on Group $($item.Name) to $user"
          
        }


    }
    
    
}

Process {

    if ($Set -eq $False) {
        Get-EmptyManagedByGroups ($OutputPath)
    }


    if ($set) {
        Set-EmptyManagedByGroup ($InputPath)
    }
  
}

End{

        Write-Log "$($MyInvocation.InvocationName) Completed"
        Write-Log '--------------------------------------------'
        
        
        #Date and Rename Log File
        if (Test-Path $logpath){
          $TimeStamp = Get-Date -Format 'yyyyMMddhhmmss'
          $logpath = Get-Childitem -Path $logpath
          Rename-Item $logpath -NewName "$($logpath.baseName)-$TimeStamp.log"
        }

}

