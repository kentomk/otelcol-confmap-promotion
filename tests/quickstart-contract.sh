#!/usr/bin/env bash
set -euo pipefail

project_root=$(cd -- "$(dirname -- "$0")/.." && pwd -P)
cd "$project_root"

quickstart_line=$(grep -n -m 1 -F '## Quick start' README.md | cut -d: -f1)
quickstart_block=$(tail -n "+$quickstart_line" README.md | sed -n '1,/^```$/p')
grep -Fxq 'mkdir -p ./bin' <<< "$quickstart_block"
grep -Fxq 'go build -o ./bin/otelcol-confmap-promotion ./cmd/otelcol-confmap-promotion' <<< "$quickstart_block"
grep -Fq "checksum_matches=\$(grep -Ec" README.md
grep -Fq "test \"\$checksum_matches\" -eq 1" README.md
grep -Fq "grep -E \"^[0-9a-fA-F]{64}  \$archive\$\" SHA256SUMS" README.md
grep -Fq "unsafe_member=\$(tar -tzf \"\$archive\" | grep -E" README.md
grep -Fq "archive contains an unsafe member path" README.md
grep -Fq "extract_dir=\$(mktemp -d)" README.md
grep -Fq "tar -xzf \"\$archive\" -C \"\$extract_dir\"" README.md
grep -Fq "mv -f \"\$HOME/.local/bin/.otelcol-confmap-promotion.new\"" README.md
grep -Fq "mv -f \"\$HOME/.local/bin/.otelcol-confmap-promotion-vet.new\"" README.md

printf '%s\n' 'quickstart contract passed: creates ./bin before the first build'
