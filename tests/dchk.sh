#!/usr/bin/env bash
# Run with: bash tests/dchk.sh

set -euo pipefail

root=$(cd "$(dirname "$0")/.." && pwd)
work=$(mktemp -d "$root/tests/.dchk.XXXXXX")
trap 'rm -rf "$work"' EXIT

export GIT_CONFIG_GLOBAL=/dev/null GIT_CONFIG_SYSTEM=/dev/null
export GIT_AUTHOR_NAME=Fixture GIT_AUTHOR_EMAIL=fixture@example.invalid
export GIT_COMMITTER_NAME=Fixture GIT_COMMITTER_EMAIL=fixture@example.invalid
export HOME="$work" DOTS_DIR="$work/repo"
mkdir -p "$work/bin" "$DOTS_DIR"
# shellcheck disable=SC2016 # Expand the message argument when the mock runs.
printf '#!/usr/bin/env sh\nprintf "%%s\\n" "$3"\n' >"$work/bin/gum"
chmod +x "$work/bin/gum"
export PATH="$work/bin:$PATH"

cd "$DOTS_DIR"
git init -q -b main
git commit -q --allow-empty -m base
base=$(git rev-parse HEAD)
git remote add fixture "$work/unused.git"
git update-ref refs/remotes/fixture/main "$base"
git branch --set-upstream-to=fixture/main main >/dev/null

check() {
    local label=$1 expected_status=$2 expected_output=$3 output status=0
    output=$(sh "$root/bin/dchk" 2>&1) || status=$?
    if [[ $status != "$expected_status" || $output != "$expected_output" ]]; then
        printf 'FAIL %s: status %s (expected %s), output: %s\n' \
            "$label" "$status" "$expected_status" "$output" >&2
        exit 1
    fi
    printf 'PASS %s\n' "$label"
}

check synced 0 ''
git commit -q --allow-empty -m local
local_head=$(git rev-parse HEAD)
check ahead 1 'Dotfiles: There are unpushed changes'
remote_head=$(printf 'remote\n' | git commit-tree "HEAD^{tree}" -p "$base")
git update-ref refs/remotes/fixture/main "$remote_head"
check diverged 1 'Dotfiles: There are unpushed changes'
git update-ref refs/remotes/fixture/main "$local_head"
check synced-after-push 0 ''
remote_head=$(printf 'next remote\n' | git commit-tree "HEAD^{tree}" -p "$local_head")
git update-ref refs/remotes/fixture/main "$remote_head"
check behind-only 0 ''

printf 'original\n' >tracked
git add tracked
check staged 1 'Dotfiles: There are changes'
git commit -q -m tracked
git update-ref refs/remotes/fixture/main HEAD
printf 'modified\n' >>tracked
check unstaged 1 'Dotfiles: There are changes'
git add tracked
git commit -q -m modified
git update-ref refs/remotes/fixture/main HEAD
printf 'new\n' >untracked
check untracked 1 'Dotfiles: There are changes'
rm untracked

git branch --unset-upstream
check no-upstream 0 ''
git branch -m feature
check non-main-warning 0 'Dotfiles: Not on main branch'
