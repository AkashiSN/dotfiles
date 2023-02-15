# starship
# https://github.com/starship/starship
Invoke-Expression (&starship init powershell)

# ghq and peco setting
function gh () {
    Set-Location $(ghq list --full-path | peco)
}

# build latex in docker
# https://hub.docker.com/r/akashisn/latexmk
function latexmk {
    docker run --rm -it --name="latexmk" -v "$(Get-Location):/workdir" akashisn/latexmk:full latexmk-ext (Split-Path $Args[0] -Leaf)
}

function pdfcrop {
    docker run --rm -it --name="pdfcrop" -v "$(Get-Location):/workdir" akashisn/latexmk:full pdfcrop (Split-Path $Args[0] -Leaf)
}

function klatexformula {
    docker run --rm -it --name="klatexformula" -v "$(Get-Location):/workdir" akashisn/latexmk:full klatexformula
}

function tmux {
    if ($Args.Length -eq 0) {
        wsl --cd ~ -e tmux
    } else {
        wsl --cd (Resolve-Path $Args[0]).Path -e tmux
    }
}

function zsh {
    if ($Args.Length -eq 0) {
        wsl --cd ~ -e zsh
    } else {
        wsl --cd (Resolve-Path $Args[0]).Path -e zsh
    }
}

function anaconda {
    & "$env:USERPROFILE/anaconda3/shell/condabin/conda-hook.ps1"
    conda activate "$env:USERPROFILE/anaconda3"
}

function encode {
    & "$env:USERPROFILE/anaconda3/python.exe" "$(Split-Path $profile -Parent)/scripts/encode.py" $Args
}

function ytdl {
    youtube-dl.exe --user-agent "Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/101.0.4951.64 Safari/537.36" `
        --referer "https://www.youtube.com/" --embed-thumbnail -f m4a -o "~/Youtube/%(uploader)s/%(epoch)s-%(title)s.%(ext)s" --min-sleep-interval 15 --max-sleep-interval 30 $Args
}

function normalize {
    $null = $(New-Item -Type Directory -Force normalize)
    ls | where { $_.Name -match "m4a" } | % { echo $_.FullName && ffmpeg-normalize $_.FullName -nt peak -t -0.5 -ar 44100 -c:a aac -b:a 128k -e "-aac_coder twoloop -empty_hdlr_name 1" -o $(Join-Path normalize $_.NameString) }
}
