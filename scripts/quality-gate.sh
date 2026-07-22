#!/usr/bin/env bash
set -euo pipefail

project_root=$(cd -- "$(dirname -- "$0")/.." && pwd)
cd "$project_root"

unformatted=$(gofmt -l -- cmd internal testdata)
test -z "$unformatted"

go test ./...
if [[ -n ${CC:-} ]]; then
  race_cc=$CC
elif command -v cc >/dev/null 2>&1; then
  race_cc=cc
elif command -v zig >/dev/null 2>&1; then
  race_cc='zig cc'
else
  printf '%s\n' 'quality gate requires CC, platform cc, or Zig for race tests' >&2
  exit 2
fi
CC="$race_cc" go test -race ./...
go vet ./...
shellcheck scripts/*.sh tests/*.sh
actionlint .github/workflows/*.yml
yq -e '.runs.using == "composite" and .inputs.binary.required == true and .inputs.route.default == "cli"' action.yml >/dev/null
yq -e '.on["release"].types[0] == "published" and .on.workflow_dispatch.inputs.tagName.required == true and .on.repository_dispatch.types[0] == "kento_release_repair"' .github/workflows/release.yml >/dev/null
scripts/test-policy.sh
scripts/policy-gate.sh
go build -o bin/otelcol-confmap-promotion ./cmd/otelcol-confmap-promotion
go build -o bin/otelcol-confmap-promotion-vet ./cmd/otelcol-confmap-promotion-vet
scripts/action-smoke.sh
scripts/test-release.sh

set +e
vet_output=$(GOPROXY=off go vet -vettool="$project_root/bin/otelcol-confmap-promotion-vet" ./testdata/fixtures/unsafe-anonymous 2>&1)
vet_status=$?
set -e
test "$vet_status" -eq 1
printf '%s\n' "$vet_output" | grep -F 'OCP001: Config promotes Helper.Unmarshal; sibling fields: encoding' >/dev/null
GOPROXY=off go vet -vettool="$project_root/bin/otelcol-confmap-promotion-vet" ./testdata/fixtures/nested-safe
GOPROXY=off go vet -vettool="$project_root/bin/otelcol-confmap-promotion-vet" ./testdata/fixtures/external-test-boundary

set +e
unsafe_output=$(bin/otelcol-confmap-promotion check ./testdata/fixtures/unsafe-anonymous 2>&1)
unsafe_status=$?
set -e
test "$unsafe_status" -eq 1
printf '%s\n' "$unsafe_output" | grep -F 'OCP001 warning testdata/fixtures/unsafe-anonymous/fixture.go:' >/dev/null
printf '%s\n' "$unsafe_output" | grep -F 'Config promotes Helper.Unmarshal; sibling fields: encoding' >/dev/null

safe_output=$(bin/otelcol-confmap-promotion check ./testdata/fixtures/nested-safe)
printf '%s\n' "$safe_output" | grep -F 'summary: packages=1 diagnostics=0 unknowns=0' >/dev/null

unknown_output=$(bin/otelcol-confmap-promotion check --format json ./testdata/fixtures/explicit-parent)
printf '%s\n' "$unknown_output" | jq -e '.schemaVersion == 1 and (.diagnostics | length) == 0 and (.unknowns | length) == 1 and .unknowns[0].parentType == "Config" and .unknowns[0].location == "testdata/fixtures/explicit-parent/fixture.go:12"' >/dev/null

set +e
boundary_output=$(bin/otelcol-confmap-promotion check --format json \
  ./testdata/fixtures/unsafe-squash \
  ./testdata/fixtures/multi-level \
  ./testdata/fixtures/alias \
  ./testdata/fixtures/generic 2>&1)
boundary_status=$?
set -e
test "$boundary_status" -eq 1
printf '%s\n' "$boundary_output" | jq -e '
  .summary.diagnostics == 4 and
  ([.diagnostics[].mechanism] | sort) == ["promotes", "promotes", "promotes", "squashes"] and
  ([.diagnostics[].methodOwner] | unique) == ["Helper"] and
  ([.diagnostics[].location] | all(startswith("testdata/fixtures/")))
' >/dev/null

boundary_unknowns=$(bin/otelcol-confmap-promotion check --format json \
  ./testdata/fixtures/generated \
  ./testdata/fixtures/build-tag)
printf '%s\n' "$boundary_unknowns" | jq -e '
  .summary.diagnostics == 0 and .summary.unknowns == 2 and
  ([.unknowns[].location] | sort) == [
    "testdata/fixtures/build-tag/unsafe_windows.go",
    "testdata/fixtures/generated/fixture.go:12"
  ]
' >/dev/null

set +e
sarif_output=$(bin/otelcol-confmap-promotion check --format sarif ./testdata/fixtures/unsafe-anonymous 2>&1)
sarif_status=$?
set -e
test "$sarif_status" -eq 1
printf '%s\n' "$sarif_output" | jq -e '
  .version == "2.1.0" and
  .runs[0].results[0].ruleId == "OCP001" and
  .runs[0].results[0].locations[0].physicalLocation.artifactLocation.uri == "testdata/fixtures/unsafe-anonymous/fixture.go" and
  .runs[0].results[0].locations[0].physicalLocation.artifactLocation.uriBaseId == "%SRCROOT%" and
  .runs[0].properties.limits.timeoutSeconds == 60
' >/dev/null

preservation_output=$(bin/otelcol-confmap-promotion check --tests --format json ./testdata/fixtures/explicit-parent)
printf '%s\n' "$preservation_output" | jq -e '
  .summary.packages == 1 and .summary.diagnostics == 0 and .summary.unknowns == 1 and
  (.unknowns[0].reason | contains("candidate names all fields"))
' >/dev/null

external_test_output=$(bin/otelcol-confmap-promotion check --tests --format json ./testdata/fixtures/external-test-boundary)
printf '%s\n' "$external_test_output" | jq -e '
  .summary.diagnostics == 0 and .summary.unknowns == 1 and
  .unknowns[0].location == "testdata/fixtures/external-test-boundary/fixture_test.go" and
  (.unknowns[0].reason | contains("external test package"))
' >/dev/null

set +e
bin/otelcol-confmap-promotion check --max-types 1 ./testdata/fixtures/unsafe-anonymous >/dev/null 2>bin/limit-error.txt
limit_status=$?
bin/otelcol-confmap-promotion check fmt >/dev/null 2>bin/outside-error.txt
outside_status=$?
bin/otelcol-confmap-promotion check ./testdata/fixtures/vendor-boundary/vendor/example.com/helper >/dev/null 2>bin/vendor-error.txt
vendor_status=$?
set -e
test "$limit_status" -eq 2
test "$outside_status" -eq 2
test "$vendor_status" -eq 2
grep -F 'type limit exceeded' bin/limit-error.txt >/dev/null
grep -F 'outside the active module' bin/outside-error.txt >/dev/null
grep -E 'vendored source|load or type errors' bin/vendor-error.txt >/dev/null
if grep -F "$project_root" bin/limit-error.txt bin/outside-error.txt bin/vendor-error.txt; then
  exit 1
fi
rm -f bin/limit-error.txt bin/outside-error.txt bin/vendor-error.txt
