On Error Resume Next
Dim objshell
set objshell=createobject("Wscript.shell")

Set args = Wscript.Arguments
strCMD = "Powershell -sta -ExecutionPolicy Bypass -file "

For Each arg In args
	strCMD = strCMD & " " & chr(34) & arg & chr(34)
Next

Err.Clear

objShell.ShellExecute strCMD, , , "runas", 1

If Err.Number <> 0 Then
	strMessage = "Error launching Powershell script." & chr(10) & "Error Number: " & Err.Number & chr(10) & "Error Source: " & Err.Source & chr(10) & "Error Description: " & Err.Description
	objShell.Popup strMessage
End If