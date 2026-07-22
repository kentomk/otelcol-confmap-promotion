#!/usr/bin/env bash
set -euo pipefail

project_root=$(cd -- "$(dirname -- "$0")/.." && pwd)
test_root=$(mktemp -d)
trap 'rm -rf -- "$test_root"' EXIT
version=v0.1.0-test.1

mkdir -p "$test_root/nonempty"
printf '%s\n' sentinel >"$test_root/nonempty/keep.txt"
set +e
SOURCE_DATE_EPOCH=0 "$project_root/scripts/package-release.sh" invalid "$test_root/invalid" >/dev/null 2>&1
invalid_version_status=$?
SOURCE_DATE_EPOCH=invalid "$project_root/scripts/package-release.sh" "$version" "$test_root/epoch" >/dev/null 2>&1
invalid_epoch_status=$?
SOURCE_DATE_EPOCH=0 "$project_root/scripts/package-release.sh" "$version" "$test_root/nonempty" >/dev/null 2>&1
nonempty_status=$?
set -e
test "$invalid_version_status" -eq 2
test "$invalid_epoch_status" -eq 2
test "$nonempty_status" -eq 2
test "$(cat "$test_root/nonempty/keep.txt")" = sentinel

SOURCE_DATE_EPOCH=0 "$project_root/scripts/package-release.sh" "$version" "$test_root/first"
SOURCE_DATE_EPOCH=0 "$project_root/scripts/package-release.sh" "$version" "$test_root/second"
cmp "$test_root/first/SHA256SUMS" "$test_root/second/SHA256SUMS"

archive_count=$(find "$test_root/first" -maxdepth 1 -type f -name '*.tar.gz' | wc -l)
test "$archive_count" -eq 4
while IFS= read -r archive; do
  name=${archive##*/}
  cmp "$archive" "$test_root/second/$name"
  entries=$(tar -tzf "$archive")
  test "$(printf '%s\n' "$entries" | wc -l)" -eq 6
  for required in otelcol-confmap-promotion otelcol-confmap-promotion-vet README.md LICENSE SECURITY.md; do
    printf '%s\n' "$entries" | grep -q "/$required$"
  done
done < <(find "$test_root/first" -maxdepth 1 -type f -name '*.tar.gz' | sort)

(
  cd "$test_root/first"
  sha256sum --check SHA256SUMS
)

case "$(uname -s)/$(uname -m)" in
  Linux/x86_64) host_target=linux_amd64 ;;
  Linux/aarch64 | Linux/arm64) host_target=linux_arm64 ;;
  Darwin/x86_64) host_target=darwin_amd64 ;;
  Darwin/arm64) host_target=darwin_arm64 ;;
  *) echo 'unsupported test host' >&2; exit 2 ;;
esac
host_root="otelcol-confmap-promotion_${version}_${host_target}"
tar -xzf "$test_root/first/$host_root.tar.gz" -C "$test_root"
cli="$test_root/$host_root/otelcol-confmap-promotion"
vettool="$test_root/$host_root/otelcol-confmap-promotion-vet"
test "$("$cli" version)" = "$version"
test "$("$vettool" version)" = "$version"

cli_metadata=$(go version -m "$cli")
vet_metadata=$(go version -m "$vettool")
printf '%s\n' "$cli_metadata" | grep -F $'build\tCGO_ENABLED=0' >/dev/null
printf '%s\n' "$vet_metadata" | grep -F $'build\tCGO_ENABLED=0' >/dev/null
printf '%s\n' "$cli_metadata" | grep -F $'path\tgithub.com/kentomk/otelcol-confmap-promotion/cmd/otelcol-confmap-promotion' >/dev/null
printf '%s\n' "$vet_metadata" | grep -F $'path\tgithub.com/kentomk/otelcol-confmap-promotion/cmd/otelcol-confmap-promotion-vet' >/dev/null
for metadata in "$cli_metadata" "$vet_metadata"; do
  printf '%s\n' "$metadata" | grep -F $'dep\tgolang.org/x/mod\tv0.30.0\th1:fDEXFVZ/fmCKProc/yAXXUijritrDzahmwwefnjoPFk=' >/dev/null
  printf '%s\n' "$metadata" | grep -F $'dep\tgolang.org/x/sync\tv0.18.0\th1:kr88TuHDroi+UVf+0hZnirlk8o8T+4MrK6mr60WkH/I=' >/dev/null
  printf '%s\n' "$metadata" | grep -F $'dep\tgolang.org/x/tools\tv0.39.0\th1:ik4ho21kwuQln40uelmciQPp9SipgNDdrafrYA4TmQQ=' >/dev/null
  if printf '%s\n' "$metadata" | grep -Eq $'build\tvcs(\\.|=)'; then
    echo 'release binary unexpectedly contains VCS provenance' >&2
    exit 1
  fi
done

printf 'release package passed: archives=4 executables=2 reproducible=true version=%s\n' "$version"
