md %homedrive%%homepath%\Documents\PowerShell
md %homedrive%%homepath%\Documents\PowerShell\Scripts
mklink %homedrive%%homepath%\Documents\PowerShell\Profile.ps1 %cd%\Profile.ps1
mklink %homedrive%%homepath%\Documents\PowerShell\Scripts\encode.py %cd%\scripts\encode.py
