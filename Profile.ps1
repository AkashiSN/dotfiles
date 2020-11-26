# Start location
Set-Location $env:HOME

if (Get-Module -ListAvailable -Name posh-git) {
    # Git module import
    Import-Module posh-git
} else {
    # Install posh-git
    PowerShellGet\Install-Module posh-git -Scope CurrentUser -AllowPrerelease -Force
    # Git module import
    Import-Module posh-git
}

# ghq and peco setting
function gh () {
    Set-Location $(ghq list --full-path | peco)
}

# build latex in docker
# https://hub.docker.com/r/arkark/latexmk
function latexmk {
    docker run --rm -it --name="latexmk" -v "$(Get-Location):/workdir" arkark/latexmk:full latexmk-ext (Split-Path $Args[0] -Leaf)
}

function pdfcrop {
    docker run --rm -it --name="pdfcrop" -v "$(Get-Location):/workdir" arkark/latexmk:full pdfcrop (Split-Path $Args[0] -Leaf)
}

function tmux {
    wsl -e tmux
}

function conda {
    & "$env:HOME/anaconda3/shell/condabin/conda-hook.ps1"
    conda activate "$env:HOME/anaconda3"
}

function encode {
    & "$env:HOME/anaconda3/python.exe" "$(Split-Path $profile -Parent)/scripts/encode.py" $Args
}

# Setting for prompt
function executetime {
    if ((Get-History).count -ge 1) {
        $executionTime = ((Get-History)[-1].EndExecutionTime - (Get-History)[-1].StartExecutionTime).Totalmilliseconds
        $time = [math]::Round($executionTime,2) / 1000
        $ts =  [timespan]::fromseconds($time)
        return ("{0:hh\:mm\:ss\,fff}" -f $ts)
    } else {
        $ts =  [timespan]::fromseconds(0)
        return ("{0:hh\:mm\:ss\,fff}" -f $ts)
    }
}

$GitPromptSettings.DefaultPromptPath.ForegroundColor = 'Orange'
$GitPromptSettings.DefaultPromptPrefix.Text = '$(executetime) '
$GitPromptSettings.DefaultPromptPrefix.ForegroundColor = [ConsoleColor]::Cyan