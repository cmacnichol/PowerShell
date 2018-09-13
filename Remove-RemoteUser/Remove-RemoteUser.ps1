function Add-LocalAdminAccount (){
  $computer = $($item.server)
  $computer = 'D2UAPKGT11'
  $pass = Convertto-SecureString -AsPlainText 'x3TtPCDV$0U6' -Force
  Set-Localuser -Computername $computer -Name 'LocalTech' -Password $pass -Description 'Application Packaging Local Admin Account'
 
}


$result = $null
$computer = $env:COMPUTERNAME
$GroupResults = @()

$input = New-InputBox -Prompt 'Enter Computer Name'

if ($input){$computer = $input}

$Selection = (Get-Localgroup -Computername $computer | Select-Object * | Out-GridView -PassThru -Title "Local Groups from Computer: $Computer")
  
#$groups = @(Get-Localgroup -Computername 'PDWCCSWS11')

foreach ($group in $selection)
 {
 
   Write-Host $($Group.name) -ForegroundColor Green
   $result = Get-LocalGroupMember -Computername 'PDWCCSWS11' -name "$($group.name)"
   
   foreach ($item in $result) {
   
     # Create Array to Store results
    $GroupResults += [PSCustomObject][Ordered]@{
       Server = $Computer
       Group = $group.name
       User = $item
       
     }#EndPSCustomObject
   }
   
 }
 
 $remove = $GroupResults | Out-GridView -PassThru -Title 'Select Users to Remove'
 
 foreach ($item in $remove){
   Remove-LocalGroupMember -GroupName $($item.Group) -Computername $($item.server) -name $($item.User) -WhatIf
   Write-Host "Removed User $($item.User) from Group $($item.group) and Server $($item.server)" -ForegroundColor Red
 }
 Get-Aduser -Server 'hbiusers.hbicorp.huntington.com' -LDAPFilter '(Surname=*Leeth*)'
 Get-Aduser -Server 'hbiusers.hbicorp.huntington.com' -Filter {(Surname -eq 'Leeth')}
 
 Add-LocalGroupMember -Computername 'VEUCWIN10PKG02' -GroupName 'Administrators' -name 'zzmc047pa'
 Add-LocalGroupMember -Computername 'D2UAPKGT11' -GroupName 'Remote Desktop Users' -name 'mk00835'
 Get-LocalgroupMember -Computername 'D2UAPKGT11' -Name 'Administrators'
 Get-LocalgroupMember -Computername 'D2UAPKGT11' -Name 'Remote Desktop Users'
 
 Remove-LocalGroupMember -Computername 'D2UAPKGT11' -GroupName 'Administrators' -name 'R_WinDesktop_LocalAdmin_U'

 Get-SCCMUserDevice -LastName Leeth
 
 $users = @('HB01600';'zztn001')
 
 $users | foreach-object { Add-LocalGroupMember -Computername 'D2UAPKGT08' -GroupName 'Remote Desktop Users' -name $_}
 
 Get-LocalGroup -Name 'Administrators' -Computername 'D2UAPKGT11'