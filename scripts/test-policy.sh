#!/usr/bin/env bash
set -euo pipefail

project_root=$(cd -- "$(dirname -- "$0")/.." && pwd)
test_root=$(mktemp -d)
trap 'rm -rf -- "$test_root"' EXIT

git -C "$test_root" init -q
printf '%s\n' 'ordinary fixture content' >"$test_root/safe.txt"
git -C "$test_root" add safe.txt
"$project_root/scripts/scan-tracked-secrets.sh" "$test_root"

printf '%s%s%s\n' '-----BEGIN ' 'PRIVATE KEY' '-----' >"$test_root/leak.txt"
git -C "$test_root" add leak.txt
set +e
scan_output=$("$project_root/scripts/scan-tracked-secrets.sh" "$test_root" 2>&1)
scan_status=$?
set -e
test "$scan_status" -eq 1
printf '%s\n' "$scan_output" | grep -F 'private key marker in leak.txt' >/dev/null

printf 'secret policy self-test passed: safe=accepted private-key=rejected\n'
