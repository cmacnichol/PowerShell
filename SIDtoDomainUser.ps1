$objSID = New-Object System.Security.Principal.SecurityIdentifier ` 
("ENTER-SID-HERE") 
$objUser = $objSID.Translate( [System.Security.Principal.NTAccount]) 
$objUser.Value