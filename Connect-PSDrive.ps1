 Function Connect-PSDrive 
 {
 
   <#

        .SYNOPSIS
        Connect-PSDrive

        .DESCRIPTION
        Connects and Disconnects a PSDrive with Error Handling.  The Logging function currently requires a separate Logging Function unless changed.

        .PARAMETER DriveName
        Used to specify a Drive Letter to attach the PS Drive to.

        .PARAMETER Path
        Specifies the network path to map the drive to.

        .PARAMETER Provider
        Specifies the System Provider to use.

        .PARAMETER Credential
        Accepts a Windows Credential object if the share needs to be mapped with different credentials.

        .PARAMETER Remove
        Removes the Specified Drive Mapping.

        .PARAMETER Status
        Will check the specified Drive Name to see if it is connected and return True or False.

        .PARAMETER Persist
        Created the PS Drive with the persist option.  This will make the mounted drive available outside the PowerShell session.

        .EXAMPLE
        Connect-PSDrive

        .EXAMPLE
        Connect-PSDrive -Remove

        .NOTES
        Author: Christopher Macnichol
        Email : christopher.macnichol@us.sogeti.com
        Phone : 740-358-0894
        Version: 0.4
        Version History: 
        0.4 - Added Persist Option
        0.3 - Added Comments and Help and Credential Check
        0.2 - Added Parameters and Logging
        0.1 - Initial Script

   #>
   param
   (
    [String]
    [Parameter(Position=0)]
    $DriveName = 'X',

    [String]
    [Parameter(Position=1)]
    $Path,

    $Credential = [System.Management.Automation.PSCredential]::Empty,

    [Parameter(Position=3)]
    $Provider = 'FileSystem',

    [Switch]
    $Remove = $false,
     
    [Switch]
    $Status,

    [Switch]
    $Persist = $false
    
   )

   begin
   {
  
     #Verfies the inputted Credential is the correct object type.
     if ($Credential.gettype().name -ne 'PSCredential') 
     {

     Write-Log -Message 'Credential is in an Incorrect format.  Defaulting to Script Authority.'
     $Credential = [System.Management.Automation.PSCredential]::Empty

     }
     else
     {

     }

   }
   process
   {
  
     if ($Remove -ne $True -and $status -ne $True) 
     {
       try {
      
         Write-Log -Message ('Connecting to Network Share {0}' -f $Path)
         
         If ($persist) {
            
            New-PSDrive -Name $DriveName -PSProvider $Provider -Root $Path -Credential $Credential -Persist -Scope Global -ErrorAction Stop | Out-Null 
                
                }

            Else { 
            
            New-PSDrive -Name $DriveName -PSProvider $Provider -Root $Path -Credential $Credential -Scope Global -ErrorAction Stop | Out-Null 

            } #End If Persist

         Write-Log -Message ('Connected to Network Share {0}' -f $DriveName)
        
          }
       catch 
       {
      
         Write-Log -Message 'Error Encountered Opening Network Share.' -Level Warn
         Write-Log -Message ('{0}' -f $Error[0].Exception.Message) -Level Error
         Write-Log -Message 'Exiting Script.' -Level Warn
         exit
        
       }

     }
     elseif($Status -eq $True -and $Remove -ne $True) 
     {
     
         Write-Log -Message ('Checking PSDrive Status for Drive Name {0}' -f $DriveName)
         if (Get-PSDrive -Name $DriveName -ErrorAction SilentlyContinue) { 
           (Write-Log -Message 'Drive Name {0} is Connected to {1}' -f $DriveName, $(Get-PSDrive -Name $DriveName).Root )

           return $true

         }
         else { 
         
           Write-Log -Message 'Drive Name {0} is Not Connected' -f $DriveName

           return $false
         
         }
     
     }
     else 
     { 
    
       try {
      
         Write-Log -Message ('Removing Network Share {0}' -f $DriveName)
         Remove-PSDrive -Name $DriveName -Force -ErrorAction Stop
        
          }
       catch 
       {
      
         Write-Log -Message 'Error Encountered Removing Network Share.' -Level Warn
         Write-Log -Message ('{0}' -f $Error[0].Exception.Message) -Level Error
         Write-Log -Message 'Exiting Script.' -Level Warn
         exit
        
       }
     }
    
   }
   end {
   
   }

  }