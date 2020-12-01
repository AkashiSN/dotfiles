# dotfiles

```bash
zsh <(curl -L https://raw.githubusercontent.com/AkashiSN/dotfiles/main/setup.zsh)
```

## zsh, git等のバージョンが古い場合

- Zsh < 5.3
- Git < 1.8.5

の場合は上記を行う前に以下を行い新しいバージョンのデプロイをする

```bash
cd build

export DOCKER_BUILDKIT=1

# Prefixを対象のホームディレクトリ似合わせてビルドを行う
sudo -E docker build -t zsh -f zsh.dockerfile --build-arg homedir={対象のホームディレクトリ} --output type=local,dest=. .
sudo -E docker build -t git -f git.dockerfile --build-arg homedir={対象のホームディレクトリ} --output type=local,dest=. .

# 転送
scp zsh.tar.xz target:
scp git.tar.xz target:

# 解凍
ssh target tar xvf zsh.tar.xz
ssh target tar xvf git.tar.xz
```
