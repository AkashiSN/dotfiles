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

function ytdlp {
    yt-dlp.exe --user-agent "Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/115.0.0.0 Safari/537.36" `
        --referer "https://www.youtube.com/" -x -f "ba[ext=webm]" -k --audio-format alac --embed-thumbnail -o "~/Music/Youtube/%(uploader)s/%(epoch)s-%(title)s.%(ext)s" $Args
}
