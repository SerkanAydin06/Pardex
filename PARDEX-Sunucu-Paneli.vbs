' PARDEX Sunucu Paneli: sunucu, yayinlama ve ag testi tek pencerede. Siyah pencere olmadan
' baslatir ve paneli acar.
' Ilk seferde (Node.js henuz yoksa) indirme ilerlemesi gorunsun diye host\pardex_sunucu.bat gorunur acilir.
Set fso = CreateObject("Scripting.FileSystemObject")
Set sh = CreateObject("WScript.Shell")
dir = fso.GetParentFolderName(WScript.ScriptFullName)
sh.CurrentDirectory = dir
bat = dir & "\host\pardex_sunucu.bat"
hasNode = fso.FileExists(dir & "\host\bin\node\node.exe") _
  Or fso.FileExists(sh.ExpandEnvironmentStrings("%ProgramFiles%") & "\nodejs\node.exe") _
  Or fso.FileExists(sh.ExpandEnvironmentStrings("%LOCALAPPDATA%") & "\Programs\nodejs\node.exe")
If hasNode Then
  sh.Run "cmd /c """"" & bat & """ --gizli""", 0, False
Else
  sh.Run """" & bat & """", 1, False
End If
