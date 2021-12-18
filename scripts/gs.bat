@REM @echo off
setlocal

echo %*

for /f "usebackq delims=" %%A in (`pwsh -noprofile -Command "%~dp0get_relative_path.ps1" "%*"`) do (
  set ARGS="%%A"
)

"C:\Program Files\Git\usr\bin\winpty.exe" "C:\Program Files\Git\bin\bash.exe"
docker run --rm -it --name="gs" -v "%CD%:/workdir" akashisn/latexmk:full gs %ARGS%
