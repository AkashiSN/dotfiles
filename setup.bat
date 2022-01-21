cd /d %~dp0

rem PowerShell Profiles
md %homedrive%%homepath%\Documents\PowerShell
del %homedrive%%homepath%\Documents\PowerShell\Profile.ps1
mklink %homedrive%%homepath%\Documents\PowerShell\Profile.ps1 %cd%\Profile.ps1

rem ssh config
md %homedrive%%homepath%\.ssh
del %homedrive%%homepath%\.ssh\config
del %homedrive%%homepath%\.ssh\gpg.pub
mklink %homedrive%%homepath%\.ssh\config %cd%\.ssh\config
mklink %homedrive%%homepath%\.ssh\gpg.pub %cd%\.ssh\gpg.pub

rem git config
del %homedrive%%homepath%\.gitconfig
copy %cd%\.gitconfig %homedrive%%homepath%\.gitconfig
git config --global gpg.program "C:/Program Files (x86)/GnuPG/bin/gpg.exe"
git config --global core.sshCommand "C:/Windows/System32/OpenSSH/ssh.exe"

pause