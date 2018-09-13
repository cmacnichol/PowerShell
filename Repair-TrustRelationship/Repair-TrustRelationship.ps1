<#
    .Synopsis
      Repair computer trust relationship.
   
    .DESCRIPTION
      

    .EXAMPLE
     

    .INPUTS
      

    .OUTPUTS
      Success or Failure

    .NOTES
     
    
    Author          : Chris Macnichol
    Version         : 0.2
    Version History : 
    0.2 - 09-28-2017 - Added Self Elevation
    0.1 - 08-31-2017 - Initial Script.

    Created         : 08/31/2017
    Last updated    : 08/31/2017
#>

#No Params or Error checking is currently implemented.
<#Param
    (
    # Param1 help description
    [Parameter(Mandatory = $false, 
      ValueFromPipeline = $true,
      ValueFromPipelineByPropertyName = $true,
      Position = 0,
    ParameterSetName = 'Parameter Set 1')]
    [Alias('ALIAS')]
    $Param1 = $null
    )
#>

# Self-elevate the script if required
if (-Not ([Security.Principal.WindowsPrincipal] [Security.Principal.WindowsIdentity]::GetCurrent()).IsInRole([Security.Principal.WindowsBuiltInRole] 'Administrator')) {
  if ([int](Get-CimInstance -Class Win32_OperatingSystem | Select-Object -ExpandProperty BuildNumber) -ge 6000) {
    $CommandLine = "-File `"" + $MyInvocation.MyCommand.Path + "`" " + $MyInvocation.UnboundArguments
    Start-Process -FilePath PowerShell.exe -Verb Runas -ArgumentList $CommandLine
    Exit
  }
}

$trust = $false
[int]$n = 1
$cred = $(Get-Credential -Message 'Please enter Credential with authority to rejoin to the Domain.')

while ($trust -eq $false -and $n -ne '5')
{
  Write-Host "Repairing Computer Secure Channel.  Attempt $n of 10"
  if (!(Test-ComputerSecureChannel -Credential $cred -Repair))
  {
    Start-Sleep -Seconds 2
    $n++
  }
  Else
  {
    $trust = $true
  }
}

if ($trust -eq $true){
  Write-Host 'Trust Relationship Repaired'
}
else
{
  Write-Host "Repair Trust Relationship Failed after $n attempts."

}
