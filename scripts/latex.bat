@echo off
setlocal

for /f "usebackq delims=" %%A in (`pwsh -noprofile -Command "%~dp0get_relative_path.ps1" "%*"`) do (
  set ARGS=%%A
)

docker run --rm --name="latex" -v "%CD%:/workdir" akashisn/latexmk:full latex %ARGS%
