#!/usr/bin/env bash
set -euo pipefail

project_root=$(cd -- "$(dirname -- "$0")/.." && pwd)
fixture_root="$project_root/testdata/runtime-comparison"
temporary_root=$(mktemp -d)
trap 'rm -rf -- "$temporary_root"' EXIT

versions=(v1.28.0 v1.29.0 v1.34.0 v1.54.0 v1.63.0)
sums=(
  'h1:pUQh4eOW0YQ1GFWTDP5pw/ZMQuppkz6oSoDDloAH/Sc='
  'h1:1d43r3gQApgRxjyiQ86/qQd7OHW/BEbM6m/L36O5gKU='
  'h1:PG4sYlLxgCMnA5F7daKXZV+NKjU1IzXBzVQeyvcwyh0='
  'h1:RUoxQ4uAYHTI57GfHh61D00tTQsXm9T88ozrAiicByc='
  'h1:1THBabHoQc8t/9r6ztMsghiO1OxDPZpYtn0cuwwsxYI='
)

cp "$fixture_root/main.go" "$fixture_root/go.mod" "$temporary_root/"
cd "$temporary_root"

for index in "${!versions[@]}"; do
  version=${versions[$index]}
  expected_sum=${sums[$index]}
  go mod edit -require="go.opentelemetry.io/collector/confmap@$version"
  metadata=$(GOWORK=off go mod download -json "go.opentelemetry.io/collector/confmap@$version")
  actual_sum=$(printf '%s\n' "$metadata" | jq -r '.Sum')
  test "$actual_sum" = "$expected_sum"
  GOWORK=off go mod tidy
  GOWORK=off go mod download all

  unsafe=$(GOWORK=off GOPROXY=off go run . unsafe)
  nested=$(GOWORK=off GOPROXY=off go run . nested)
  ignored=$(GOWORK=off GOPROXY=off go run . ignore)

  printf '%s\n' "$unsafe" | jq -e \
    '.mode == "unsafe" and .outcome == "rejected-sibling" and .encoding == "" and .queueSize == 17' >/dev/null
  printf '%s\n' "$nested" | jq -e \
    '.mode == "nested" and .outcome == "preserved" and .encoding == "otlp" and .queueSize == 17' >/dev/null
  printf '%s\n' "$ignored" | jq -e \
    '.mode == "ignore" and .outcome == "silent-sibling-loss" and .encoding == "" and .queueSize == 17' >/dev/null
  printf '%s %s\n' "$version" 'unsafe=rejected nested=preserved ignore=silent-sibling-loss'
done
