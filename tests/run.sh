#!/usr/bin/env bash
# tests/**/*.test.sh を順に実行し、1 つでも失敗すれば非 0 で終わる。
set -u
cd "$(dirname "$0")" || exit 1
rc=0
while IFS= read -r t; do
	echo "== $t"
	bash "$t" || rc=1
done < <(find . -name '*.test.sh' | sort)
exit $rc
