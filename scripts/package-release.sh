#!/usr/bin/env bash
set -euo pipefail

if [[ $# -ne 2 ]]; then
  echo 'usage: scripts/package-release.sh VERSION OUTPUT_DIRECTORY' >&2
  exit 2
fi

version=$1
output_directory=$2
if [[ ! "$version" =~ ^v[0-9]+\.[0-9]+\.[0-9]+([.-][0-9A-Za-z.-]+)?$ ]]; then
  echo 'invalid semantic version' >&2
  exit 2
fi

project_root=$(cd -- "$(dirname -- "$0")/.." && pwd)
case "$output_directory" in
  /*) ;;
  *) output_directory="$project_root/$output_directory" ;;
esac
mkdir -p "$output_directory"
output_directory=$(cd -- "$output_directory" && pwd)
if find "$output_directory" -mindepth 1 -print -quit | grep -q .; then
  echo 'output directory must be empty' >&2
  exit 2
fi

source_date_epoch=${SOURCE_DATE_EPOCH:-0}
if [[ ! "$source_date_epoch" =~ ^[0-9]+$ ]]; then
  echo 'SOURCE_DATE_EPOCH must be a non-negative integer' >&2
  exit 2
fi

build_root=$(mktemp -d)
trap 'rm -rf -- "$build_root"' EXIT
targets=(linux/amd64 linux/arm64 darwin/amd64 darwin/arm64)
archives=()

for target in "${targets[@]}"; do
  target_os=${target%/*}
  target_arch=${target#*/}
  archive_root="otelcol-confmap-promotion_${version}_${target_os}_${target_arch}"
  package_directory="$build_root/$archive_root"
  mkdir -p "$package_directory"

  (
    cd "$project_root"
    export CGO_ENABLED=0 GOOS="$target_os" GOARCH="$target_arch"
    export GOTOOLCHAIN=local GOPROXY=off GOSUMDB=off GOWORK=off
    build_flags=(-trimpath -buildvcs=false -ldflags "-buildid= -s -w -X main.version=$version")
    go build "${build_flags[@]}" -o "$package_directory/otelcol-confmap-promotion" ./cmd/otelcol-confmap-promotion
    go build "${build_flags[@]}" -o "$package_directory/otelcol-confmap-promotion-vet" ./cmd/otelcol-confmap-promotion-vet
  )

  cp "$project_root/README.md" "$project_root/LICENSE" "$project_root/SECURITY.md" "$package_directory/"
  chmod 0755 "$package_directory/otelcol-confmap-promotion" "$package_directory/otelcol-confmap-promotion-vet"
  chmod 0644 "$package_directory/README.md" "$package_directory/LICENSE" "$package_directory/SECURITY.md"

  archive="$output_directory/$archive_root.tar.gz"
  tar --sort=name --format=ustar --owner=0 --group=0 --numeric-owner \
    --mtime="@$source_date_epoch" -C "$build_root" -cf - "$archive_root" |
    gzip -n -9 >"$archive"
  archives+=("${archive##*/}")
done

(
  cd "$output_directory"
  sha256sum "${archives[@]}" >SHA256SUMS
)

printf 'packaged %s reproducible archives for %s\n' "${#archives[@]}" "$version"
