# shellcheck shell=bash
# apply のたびに共有ストア (/opt) の食い違いを調べ、必要なときだけ sudo で揃える。bash。
# .chezmoiscripts の run_after_15 が template "shared-store-trigger.sh" で取り込む。
# テンプレートの記法は含めない（tests/ からそのまま source できる）。
# 前提: bootstrap/lib.sh と bootstrap/guard.sh を source 済み。note/warn は lib.sh のもの。
# 環境変数: DOTFILES_SRC（ソースのパス）、SHARED_ROOT（既定 /opt）。

# shared_store_trigger
# 常に 0 を返す。共有ストアの都合で apply を止めない。
shared_store_trigger() {
	local src="${DOTFILES_SRC:?}" root="${SHARED_ROOT:-/opt}" rc=0 verdict state

	# 一致していれば sudo を呼ばず終わる。1 が食い違い、それ以外は判定の異常。
	bash "$src/bootstrap/run-all.sh" --check || rc=$?
	case "$rc" in
	0) return 0 ;;
	1) ;;
	*)
		warn "共有ストアの確認に失敗しました (run-all.sh --check: $rc)。共有側は更新しません"
		return 0
		;;
	esac

	# git は root で動かすと dubious ownership で拒否されるため、利用者のこの権限で判定する。
	# ok なら HEAD を state へ書かせる。force は state を書かせない。
	state="$root/dotfiles-shared/state"
	rc=0
	verdict="$(shared_guard "$src" "$state")" || rc=$?
	if [ "$rc" -ne 0 ]; then
		warn "共有ストアに食い違いがありますが更新しません: $(shared_guard_hint "${verdict#stale:}")"
		return 0
	fi

	if ! sudo -n true 2>/dev/null && [ ! -t 0 ]; then
		warn "共有ストアの更新を飛ばしました（sudo を使えません）"
		note "端末から chezmoi apply を実行すると更新されます"
		return 0
	fi

	note "共有ストア (${root}) を更新します（sudo）"
	# 秘密は argv に載せない（ps で見える）ため、export して sudo に引き継がせる。
	DOTFILES_SRC="$src"
	AQUA_BIN="$(command -v aqua || true)"
	GITHUB_TOKEN="$(gh auth token 2>/dev/null || true)"
	SHARED_ROOT="$root"
	if [ "$verdict" = force ]; then
		DOTFILES_SHARED_FORCE=1
		DOTFILES_STATE_COMMIT=
	else
		DOTFILES_SHARED_FORCE=
		DOTFILES_STATE_COMMIT="$(git -C "$src" rev-parse HEAD)"
	fi
	export DOTFILES_SRC AQUA_BIN GITHUB_TOKEN SHARED_ROOT DOTFILES_SHARED_FORCE DOTFILES_STATE_COMMIT
	if ! sudo --preserve-env=DOTFILES_SRC,AQUA_BIN,GITHUB_TOKEN,DOTFILES_SHARED_FORCE,DOTFILES_STATE_COMMIT,SHARED_ROOT \
		bash "$src/bootstrap/run-all.sh"; then
		warn "共有ストアの更新に失敗しました（sudo を断られた、またはステップが失敗）。次の apply で再試行します"
	fi
	return 0
}
