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

printf '%s\n' 'quickstart contract passed: creates ./bin before the first build'
