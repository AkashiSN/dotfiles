# shellcheck shell=bash
# apply のたびに共有ストア (/opt) の食い違いを調べ、必要なときだけ sudo で揃える。bash。
# .chezmoiscripts の run_after_15 が template "shared-store-trigger.sh" で取り込む。
# テンプレートの記法は含めない（tests/ からそのまま source できる）。
# 前提: bootstrap/lib.sh と bootstrap/guard.sh を source 済み。note/warn は lib.sh のもの。
# 環境変数: DOTFILES_SRC（ソースのパス）、SHARED_ROOT（既定 /opt）、
#           DOTFILES_SHARED_SKIP=1（食い違いがあっても sudo を呼ばず、案内 1 行で終える）。

# shared_store_trigger
# 常に 0 を返す。共有ストアの都合で apply を止めない。
# sudo の認証やロックを待つ間にほかのユーザが共有側を更新すると、run-all.sh は何もせず 4 で終わる。
# そのときは 1 度だけ判定からやり直す。
shared_store_trigger() {
	_shared_store_trigger_once && return 0
	note "判定のあとにほかのユーザが共有ストアを更新したため、判定し直します"
	_shared_store_trigger_once && return 0
	note "共有ストアの更新が続いているため見送りました。次の apply で判定し直します"
	return 0
}

# _shared_store_trigger_once
# 判定から sudo までを 1 回流す。run-all.sh が 4（判定が古い）で終わったときだけ 1、ほかは 0。
_shared_store_trigger_once() {
	local src="${DOTFILES_SRC:?}" root="${SHARED_ROOT:-/opt}" rc=0 verdict state seen pending_only=0 nflag=""

	# 一致していれば sudo を呼ばず終わる。1 がキーの食い違い、3 が消し残し（使用中で残した古い版）だけ、
	# それ以外は判定の異常。
	bash "$src/bootstrap/run-all.sh" --check || rc=$?
	case "$rc" in
	0) return 0 ;;
	1) ;;
	3) pending_only=1 ;;
	*)
		warn "共有ストアの確認に失敗しました (run-all.sh --check: $rc)。共有側は更新しません"
		return 0
		;;
	esac

	if [ "${DOTFILES_SHARED_SKIP:-}" = 1 ]; then
		note "DOTFILES_SHARED_SKIP=1 のため、共有ストア (${root}) の更新を飛ばしました"
		return 0
	fi

	# git は root で動かすと dubious ownership で拒否されるため、利用者のこの権限で判定する。
	# ok なら HEAD を state へ書かせる。force は state を書かせない。
	# 判定に使う state を先に読み、run-all.sh がロックを取ってから同じかを確かめる。判定より前に
	# 読むので、間で state が進めば run-all.sh 側で食い違い、古い判定のまま更新することはない。
	state="$root/dotfiles-shared/state"
	seen="$(state_commit "$state")"
	rc=0
	verdict="$(shared_guard "$src" "$state")" || rc=$?
	if [ "$rc" -ne 0 ]; then
		if [ "$pending_only" -eq 1 ]; then
			note "共有ストアの消し残しの掃除を見送りました: $(shared_guard_hint "${verdict#stale:}")"
		else
			warn "共有ストアに食い違いがありますが更新しません: $(shared_guard_hint "${verdict#stale:}")"
		fi
		return 0
	fi

	# 消し残しの掃除だけなら急がない。パスワードを聞かず、sudo -n が通るときだけ流す。
	if [ "$pending_only" -eq 1 ]; then
		if ! sudo -n true 2>/dev/null; then
			note "共有ストアに使用中で残した古い版があります。sudo をパスワードなしで使える apply で掃除します"
			return 0
		fi
		nflag=1
	elif ! sudo -n true 2>/dev/null && [ ! -t 0 ]; then
		warn "共有ストアの更新を飛ばしました（sudo を使えません）"
		note "端末から chezmoi apply を実行すると更新されます"
		return 0
	fi

	if [ "$pending_only" -eq 1 ]; then
		note "共有ストア (${root}) の消し残しを掃除します（sudo）"
	else
		note "共有ストア (${root}) を更新します（sudo）"
	fi
	# 秘密は argv に載せない（ps で見える）ため、export して sudo に引き継がせる。
	DOTFILES_SRC="$src"
	# 初回の apply では ~/.local/bin などがまだ PATH に無いため、10-install-packages の置き場も探す。
	AQUA_BIN="$(
		PATH="$PATH:$HOME/.local/bin:/opt/homebrew/bin:/usr/local/bin"
		command -v aqua || true
	)"
	# 設定済みの GITHUB_TOKEN があればそれを使う。
	GITHUB_TOKEN="${GITHUB_TOKEN:-$(gh auth token 2>/dev/null || true)}"
	SHARED_ROOT="$root"
	if [ "$verdict" = force ]; then
		DOTFILES_SHARED_FORCE=1
		DOTFILES_STATE_COMMIT=
		DOTFILES_STATE_SEEN=
	else
		DOTFILES_SHARED_FORCE=
		DOTFILES_STATE_COMMIT="$(git -C "$src" rev-parse HEAD)"
		DOTFILES_STATE_SEEN="$seen"
	fi
	export DOTFILES_SRC AQUA_BIN GITHUB_TOKEN SHARED_ROOT DOTFILES_SHARED_FORCE DOTFILES_STATE_COMMIT DOTFILES_STATE_SEEN
	rc=0
	sudo ${nflag:+-n} --preserve-env=DOTFILES_SRC,AQUA_BIN,GITHUB_TOKEN,DOTFILES_SHARED_FORCE,DOTFILES_STATE_COMMIT,DOTFILES_STATE_SEEN,SHARED_ROOT \
		bash "$src/bootstrap/run-all.sh" || rc=$?
	[ "$rc" -ne 4 ] || return 1
	if [ "$rc" -ne 0 ]; then
		if [ "$pending_only" -eq 1 ]; then
			note "共有ストアの消し残しの掃除に失敗しました。次の apply で再試行します"
		else
			warn "共有ストアの更新に失敗しました（sudo を断られた、またはステップが失敗）。次の apply で再試行します"
		fi
	fi
	return 0
}
