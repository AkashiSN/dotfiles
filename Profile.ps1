# Start location
Set-Location $env:USERPROFILE

# starship
# https://github.com/starship/starship
Invoke-Expression (&starship init powershell)

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

function anaconda {
    & "$env:USERPROFILE/anaconda3/shell/condabin/conda-hook.ps1"
    conda activate "$env:USERPROFILE/anaconda3"
}

function encode {
    & "$env:USERPROFILE/anaconda3/python.exe" "$(Split-Path $profile -Parent)/scripts/encode.py" $Args
}
