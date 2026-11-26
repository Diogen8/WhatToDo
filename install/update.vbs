' Pulls the latest WhatToDo quietly. Run by the "WhatToDo update" scheduled task (install.ps1).
Set fso = CreateObject("Scripting.FileSystemObject")
addonDir = fso.GetParentFolderName(fso.GetParentFolderName(WScript.ScriptFullName))
Set sh = CreateObject("WScript.Shell")
git = "git"
For Each p In Array(sh.ExpandEnvironmentStrings("%ProgramFiles%\Git\cmd\git.exe"), sh.ExpandEnvironmentStrings("%LOCALAPPDATA%\Programs\Git\cmd\git.exe"))
  If fso.FileExists(p) Then git = """" & p & """"
Next
sh.Run git & " -C """ & addonDir & """ pull --ff-only --quiet", 0, False
