# 共有ストア（/opt）の 2 ユーザ通し検証用。Ubuntu LTS に alice / bob（どちらも NOPASSWD の sudo）を置く。
# 使い方は tests/docker/run.sh。chezmoi は新しい Linux ユーザと同じく公式のインストールスクリプトで入れる。
FROM ubuntu:24.04

ENV DEBIAN_FRONTEND=noninteractive LANG=C.UTF-8

# run_onchange_before_10-install-packages の apt 一覧は apply のたびに sudo apt-get で入るが、
# 検証を速くするため先に入れておく。python3 は tests/renovate とテスト用のピン変更、procps は ps / pgrep 用。
RUN apt-get update && apt-get install -y --no-install-recommends \
	sudo git curl zsh ca-certificates tmux sqlite3 build-essential xz-utils unzip zstd \
	bubblewrap file python3 procps less \
	&& rm -rf /var/lib/apt/lists/*

RUN sh -c "$(curl -fsLS get.chezmoi.io)" -- -b /usr/local/bin

# sudo の実行を 1 行ずつ /var/log/sudo.log に残す（誰が何回 run-all.sh を流したかの証跡）。
RUN for u in alice bob; do useradd -m -s /bin/zsh "$u"; done \
	&& printf '%s\n' 'Defaults logfile=/var/log/sudo.log' 'Defaults loglinelen=0' \
		'alice ALL=(ALL) NOPASSWD: ALL' 'bob ALL=(ALL) NOPASSWD: ALL' >/etc/sudoers.d/e2e \
	&& chmod 440 /etc/sudoers.d/e2e \
	&& visudo -c

CMD ["sleep", "infinity"]
