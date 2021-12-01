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

function zsh {
    wsl -e zsh
}

function anaconda {
    & "$env:USERPROFILE/anaconda3/shell/condabin/conda-hook.ps1"
    conda activate "$env:USERPROFILE/anaconda3"
}

function encode {
    & "$env:USERPROFILE/anaconda3/python.exe" "$(Split-Path $profile -Parent)/scripts/encode.py" $Args
}

function ytdl {
    youtube-dl.exe --user-agent "Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/96.0.4664.45 Safari/537.36" `
        --referer "https://www.youtube.com/" --embed-thumbnail -f m4a -o "~/Youtube/%(uploader)s/%(epoch)s-%(title)s.%(ext)s" --min-sleep-interval 5 --max-sleep-interval 15 $Args
}

function normalize {
    $null = $(New-Item -Type Directory -Force normalize)
    ls | where { $_.Name -match "m4a" } | % { echo $_.FullName && ffmpeg-normalize $_.FullName -nt peak -t -0.5 -ar 44100 -c:a aac -b:a 128k -e "-aac_coder twoloop -empty_hdlr_name 1" -o $(Join-Path normalize $_.NameString) }
}

function proxy-docker {
    ssh -L 12375:localhost:2375 i9-11000k
}

function rdocker {
    docker -H localhost:12375 $Args
}