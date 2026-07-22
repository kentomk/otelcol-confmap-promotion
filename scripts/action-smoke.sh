#!/usr/bin/env bash
set -euo pipefail

project_root=$(cd -- "$(dirname -- "$0")/.." && pwd)
cli="$project_root/bin/otelcol-confmap-promotion"
vettool="$project_root/bin/otelcol-confmap-promotion-vet"
runner="$project_root/scripts/action-run.sh"
literal_package=$(printf '%s' '$' '(touch bin/action-injection)')
cd "$project_root"

INPUT_BINARY="$cli" INPUT_ROUTE=cli INPUT_PACKAGES='./testdata/fixtures/nested-safe' INPUT_FORMAT=json INPUT_TESTS=false "$runner" >/dev/null

set +e
INPUT_BINARY="$cli" INPUT_ROUTE=cli INPUT_PACKAGES='./testdata/fixtures/unsafe-anonymous' INPUT_FORMAT=text INPUT_TESTS=false "$runner" >bin/action-cli-warning.txt 2>&1
cli_warning_status=$?
INPUT_BINARY="$cli" INPUT_ROUTE=cli INPUT_PACKAGES='./testdata/fixtures/nested-safe' INPUT_FORMAT=invalid INPUT_TESTS=false "$runner" >bin/action-cli-error.txt 2>&1
cli_error_status=$?
INPUT_BINARY="$vettool" INPUT_ROUTE=vet INPUT_PACKAGES='./testdata/fixtures/unsafe-anonymous' INPUT_FORMAT=text INPUT_TESTS=false "$runner" >bin/action-vet-warning.txt 2>&1
vet_warning_status=$?
INPUT_BINARY="$cli" INPUT_ROUTE=cli INPUT_PACKAGES="$literal_package" INPUT_FORMAT=text INPUT_TESTS=false "$runner" >/dev/null 2>bin/action-literal-error.txt
literal_status=$?
set -e

test "$cli_warning_status" -eq 1
test "$cli_error_status" -eq 2
test "$vet_warning_status" -eq 1
test "$literal_status" -eq 2
test ! -e bin/action-injection
grep -F 'OCP001 warning' bin/action-cli-warning.txt >/dev/null
grep -F 'format must be text, json, or sarif' bin/action-cli-error.txt >/dev/null
grep -F 'OCP001: Config promotes Helper.Unmarshal' bin/action-vet-warning.txt >/dev/null
rm -f bin/action-cli-warning.txt bin/action-cli-error.txt bin/action-vet-warning.txt bin/action-literal-error.txt
