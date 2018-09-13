On Error Resume Next
Dim objshell
set objshell=createobject("Wscript.shell")

Set args = Wscript.Arguments
strCMD = "Powershell -sta -ExecutionPolicy Bypass -file "
strCMD2 = "Powershell -sta -ExecutionPolicy Bypass -file "
strArgs = ""
FilePath = ""
strCompare = " "
For Each arg In args
	strCMD = strCMD & " " & chr(34) & arg & chr(34)
	strCompare = UCase(arg)
	if inStr(strCompare, ".PS1") then
		FilePath = strCompare
	end if
	strArgs = strArgs & " " & chr(34) & arg & chr(34)
Next

Err.Clear

objShell.Run strCMD,0

If Err.Number <> 0 Then
	strMessage = "Error launching Powershell script." & chr(10) & "Error Number: " & Err.Number & chr(10) & "Error Source: " & Err.Source & chr(10) & "Error Description: " & Err.Description
	objShell.Popup strMessage
End If

Set FSO = CreateObject("Scripting.FileSystemObject")
Set objFile = FSO.GetFile(FilePath)
analyticsPath = objFile.Path
analyticsName = objFile.Name
analyticsPath = Left(analyticsPath, Len(analyticsPath)-Len(analyticsName))
strCMD2 = strCMD2 & chr(34) & analyticsPath & "Analytics.PS1" & chr(34) & " " & strCMD
'objShell.Popup strCMD2
'objShell.Run strCMD2,0