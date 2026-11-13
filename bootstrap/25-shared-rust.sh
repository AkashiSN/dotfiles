#!/usr/bin/env bash
# Rust の toolchain を共有ストア $SHARED_ROOT/rustup に置く。root で実行する。
#   25-shared-rust.sh --check   共有側がソースのピンと一致するか（0 一致 / 1 食い違い）。何も書かない。
#   25-shared-rust.sh           toolchain を入れ、既定にし、古い toolchain を掃除して、キーを書く。
# 環境変数: DOTFILES_SRC / SHARED_ROOT（既定 /opt）/ AQUA_BIN（呼び出しユーザの aqua の絶対パス）。
#
# 配置:
#   $SHARED_ROOT/rustup       RUSTUP_HOME。toolchain と settings.toml（既定の toolchain）。
#   $SHARED_ROOT/cargo/bin    CARGO_HOME/bin。cargo / rustc / rustup などのプロキシ（rustup-init が置く）。
#
# 各ユーザは ~/.config/shell/env.sh で RUSTUP_HOME=$SHARED_ROOT/rustup を読み取り専用で使い、
# PATH の $SHARED_ROOT/cargo/bin からプロキシを引く。CARGO_HOME（レジストリのキャッシュと
# cargo install の出力先）はユーザごとのまま。既定の toolchain は root が書く settings.toml から
# 解決されるので、ユーザ側で RUSTUP_TOOLCHAIN を設定する必要は無い。
#
# rustup 本体は共有 aqua ストア（aqua.yaml のピン）の rustup-init から入れる。toolchain の版は下の
# RUST_VERSION で固定する（Renovate が上げる）。名前（key）は RUST_VERSION・コンポーネント・
# rustup のピンから決まり、どれかが変わると入れ直す。変わらなければ取得しない。
#
# 共有側の toolchain は読み取り専用なので、プロジェクトの rust-toolchain.toml が別の toolchain を
# 求めても各ユーザは自動で入れられない（docs/zsh-cheatsheet.md）。
set -euo pipefail

here="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source-path=SCRIPTDIR source=lib.sh
. "$here/lib.sh"

SHARED_ROOT="${SHARED_ROOT:-/opt}"
DOTFILES_SRC="${DOTFILES_SRC:-$(dirname "$here")}"
RUSTUP_ROOT="$SHARED_ROOT/rustup"
CARGO_ROOT="$SHARED_ROOT/cargo"
KEYFILE="$SHARED_ROOT/dotfiles-shared/keys/25"
AQUA_STORE="$SHARED_ROOT/aquaproj-aqua"

RUST_VERSION="1.100.0"
# minimal に足すコンポーネント（rustup の default プロファイルのうち minimal に無いもの）。
RUST_COMPONENTS="clippy rustfmt rust-docs"
# 入れたあとに toolchain の bin に実行ファイルがあるか確かめるもの。
RUST_BINARIES="rustc cargo rustfmt cargo-clippy clippy-driver"

# キーは RUST_VERSION・コンポーネント・rustup のピン（aqua.yaml の rust-lang/rustup@... の行）から決める。
src_key() {
	local pin
	pin="$(grep -E '^[[:space:]]*-[[:space:]]*name:[[:space:]]*rust-lang/rustup@' "$DOTFILES_SRC/dot_config/aquaproj-aqua/aqua.yaml" | head -1 || true)"
	pins_key <(printf 'rust-1\n%s\n%s\n%s\n' "$RUST_VERSION" "$RUST_COMPONENTS" "$pin")
}

if [ "${1:-}" = "--check" ]; then
	[ -f "$KEYFILE" ] && [ "$(cat "$KEYFILE")" = "$(src_key)" ]
	exit
fi

if [ "${BOOTSTRAP_ALLOW_NONROOT:-}" != 1 ] && [ "$(id -u)" -ne 0 ]; then
	echo "root で実行してください" >&2
	exit 1
fi
if [ -z "${AQUA_BIN:-}" ] || [ ! -x "$AQUA_BIN" ]; then
	echo "AQUA_BIN が空か実行できません（呼び出したユーザの aqua の絶対パスを渡す）: '${AQUA_BIN:-}'" >&2
	exit 1
fi
# rustup-init は共有 aqua から引く。揃えるのは 20 の役目なので、揃っていなければここでは進めない。
if ! shared_aqua_current >/dev/null 2>&1; then
	echo "共有 aqua ストア ($AQUA_STORE) がこのソースのピンと揃っていないため、このステップは飛ばします（先に bootstrap/20-shared-aqua.sh を通してください）" >&2
	exit 1
fi

umask 022
owner_group="$(shared_owner_group)"
# root のときだけ所有者を揃える（テストは一般ユーザで流す）。
set_owner() {
	[ "$(id -u)" -ne 0 ] || chown "$@"
}

# 作業ディレクトリに rust-toolchain.toml や aqua.yaml があると拾われるため、ルートへ移る。
cd /
export AQUA_ROOT_DIR="$AQUA_STORE"
export AQUA_GLOBAL_CONFIG="$AQUA_STORE/config/aqua.yaml"
export AQUA_POLICY_CONFIG="$AQUA_STORE/config/aqua-policy.yaml"
export AQUA_DISABLE_LAZY_INSTALL=true

RUSTUP_INIT="$("$AQUA_BIN" which rustup-init 2>/dev/null || true)"
if [ -z "$RUSTUP_INIT" ] || [ ! -x "$RUSTUP_INIT" ]; then
	echo "共有 aqua ストアに rustup-init がありません。先に bootstrap/20-shared-aqua.sh を実行し、aqua.yaml に rust-lang/rustup があるか確かめてください" >&2
	exit 1
fi

# 呼び出し元の環境や設定に引きずられない。toolchain の指定や PATH 上の別の rustc で止まらない。
unset RUSTUP_TOOLCHAIN RUSTUP_DIST_SERVER RUSTUP_UPDATE_ROOT
export RUSTUP_HOME="$RUSTUP_ROOT" CARGO_HOME="$CARGO_ROOT"
export RUSTUP_INIT_SKIP_PATH_CHECK=yes
RUSTUP="$CARGO_ROOT/bin/rustup"

log "共有ディレクトリ ${RUSTUP_ROOT} / ${CARGO_ROOT} を準備 (${owner_group})"
mkdir -p "$RUSTUP_ROOT" "$CARGO_ROOT"
set_owner "$owner_group" "$RUSTUP_ROOT" "$CARGO_ROOT"
chmod 755 "$RUSTUP_ROOT" "$CARGO_ROOT"

# settings.toml の既定の toolchain 名（無ければ空）。
current_default() {
	[ -f "$RUSTUP_ROOT/settings.toml" ] || return 0
	sed -n 's/^default_toolchain *= *"\(.*\)"$/\1/p' "$RUSTUP_ROOT/settings.toml" | head -1
}

# <version> の toolchain のディレクトリ名（<version>-<host>）。無ければ空。
toolchain_dir_for() {
	local d
	for d in "$RUSTUP_ROOT/toolchains/$1"-*; do
		[ -d "$d" ] && basename "$d" && return 0
	done
	return 0
}

# toolchain <tc>（ディレクトリ名）にコンポーネントの実行ファイルが揃い、動くか確かめる。
verify_toolchain() {
	local tc="$1" b
	for b in $RUST_BINARIES; do
		if [ ! -x "$RUSTUP_ROOT/toolchains/$tc/bin/$b" ]; then
			echo "$b の実行ファイルが toolchain $tc にありません" >&2
			return 1
		fi
	done
	"$RUSTUP_ROOT/toolchains/$tc/bin/rustc" --version >/dev/null || return 1
	for b in rustup cargo rustc; do
		if [ ! -x "$CARGO_ROOT/bin/$b" ]; then
			echo "$b のプロキシが $CARGO_ROOT/bin にありません" >&2
			return 1
		fi
	done
}

# rustup とプロキシを入れ、RUST_VERSION の toolchain を入れて確かめ、既定にする。
# 失敗したら入れた toolchain を（元から無かったときだけ）消して非 0 を返す。既定は変えない。
install_rust() {
	local had comp="" c tc
	had="$(toolchain_dir_for "$RUST_VERSION")"
	# toolchain は入れない（none）。既定の toolchain も変えない。プロキシと rustup 本体だけ置く。
	"$RUSTUP_INIT" -y --no-modify-path --profile minimal --default-toolchain none || return 1
	"$RUSTUP" set auto-self-update disable || return 1
	for c in $RUST_COMPONENTS; do
		comp="$comp -c $c"
	done
	# shellcheck disable=SC2086
	"$RUSTUP" toolchain install "$RUST_VERSION" --profile minimal --no-self-update $comp || return 1
	tc="$(toolchain_dir_for "$RUST_VERSION")"
	if [ -z "$tc" ] || ! verify_toolchain "$tc"; then
		[ -n "$had" ] || { [ -z "$tc" ] || "$RUSTUP" toolchain uninstall "$tc" || true; }
		return 1
	fi
	"$RUSTUP" default "$RUST_VERSION" || return 1
}

prev="$(current_default)"
log "rustup と Rust $RUST_VERSION を入れる"
if ! install_rust; then
	echo "Rust の toolchain を入れられませんでした。既定の toolchain は変えません" >&2
	exit 1
fi
NEW="$(toolchain_dir_for "$RUST_VERSION")"
if [ "$(current_default)" != "$NEW" ]; then
	echo "既定の toolchain が $NEW になっていません: '$(current_default)'" >&2
	exit 1
fi

set_owner -R "$owner_group" "$RUSTUP_ROOT" "$CARGO_ROOT"
# 展開したアーカイブの権限に関わらず、全ユーザが読めて root だけが書ける状態にする。
chmod -R a+rX,go-w "$RUSTUP_ROOT" "$CARGO_ROOT"
mkdir -p "$(dirname "$KEYFILE")"
src_key >"$KEYFILE"

# プロキシ（$CARGO_ROOT/bin の下の名前）が動いているか。macOS の ps は PATH 上のプロキシで起動した
# プロセスをそのプロキシのパスで出し、実体の toolchain は出さないことがある。
proxy_busy() {
	local f
	for f in "$CARGO_ROOT"/bin/*; do
		[ -e "$f" ] || continue
		running_exact "$f" && return 0
	done
	return 1
}

# toolchain <tc> の実体が動いているか。
toolchain_busy() {
	local tc="$1"
	running_from_any "$RUSTUP_ROOT/toolchains/$tc" && return 0
	running_matching "/rustup/toolchains/$tc/" && return 0
	running_args_matching "/rustup/toolchains/$tc" && return 0
	return 1
}

# 1 つ前の既定は残す。同じ版で入れ直した（prev が NEW と同じ）ときは、実際の 1 つ前が分からないため、
# NEW 以外で mtime が最も新しい toolchain を残す。
if [ "$prev" = "$NEW" ] || [ -z "$prev" ]; then
	best=""
	for d in "$RUSTUP_ROOT"/toolchains/*/; do
		d="${d%/}"
		[ -d "$d" ] || continue
		[ "$(basename "$d")" = "$NEW" ] && continue
		if [ -z "$best" ] || [ "$d" -nt "$best" ]; then
			best="$d"
		fi
	done
	prev=""
	[ -z "$best" ] || prev="$(basename "$best")"
fi

# 消す候補（NEW と 1 つ前以外）。候補が無ければ、プロキシが動いていても次回へ回すものは無い。
candidates=()
for d in "$RUSTUP_ROOT"/toolchains/*/; do
	d="${d%/}"
	[ -d "$d" ] || continue
	tc="$(basename "$d")"
	[ "$tc" = "$NEW" ] && continue
	[ -n "$prev" ] && [ "$tc" = "$prev" ] && continue
	candidates+=("$tc")
done

if [ "${#candidates[@]}" -gt 0 ]; then
	log "使わなくなった toolchain を削除"
	if proxy_busy; then
		note "共有のプロキシが動いているため、古い toolchain は次回に回します"
		gc_defer
	else
		for tc in "${candidates[@]}"; do
			d="$RUSTUP_ROOT/toolchains/$tc"
			if toolchain_busy "$tc"; then
				note "使用中のため残します: $d"
				gc_defer
				continue
			fi
			note "削除: $d"
			"$RUSTUP" toolchain uninstall "$tc" || rm -rf "$d"
		done
	fi
fi

log "完了: Rust $RUST_VERSION を ${RUSTUP_ROOT} に置きました"
note "各ユーザは ~/.config/shell/env.sh の RUSTUP_HOME と PATH（${CARGO_ROOT}/bin）から使います"
