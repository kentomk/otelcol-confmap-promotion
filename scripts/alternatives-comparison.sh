#!/usr/bin/env bash
set -euo pipefail

project_root=$(cd -- "$(dirname -- "$0")/.." && pwd)
comparison_root=$(mktemp -d)
trap 'rm -rf -- "$comparison_root"' EXIT
tools_bin="$comparison_root/bin"
mkdir -p "$tools_bin"

schemagen_module=go.opentelemetry.io/collector/cmd/schemagen
schemagen_version=v0.157.0
schemagen_sum='h1:vVhlz44ZfqHFTneJmT4S9i/QiW0TW8hB6KRqQ9MKcFc='
staticcheck_module=honnef.co/go/tools
staticcheck_version=v0.7.0
staticcheck_sum='h1:w6WUp1VbkqPEgLz4rkBzH/CSU6HkoqNLp6GstyTx3lU='
collector_archive_sum=e6cb5fc686c8f300ef25fec30ee39637a4f0832d30682b67ad593676627bb2da

verify_module_sum() {
  local module=$1
  local version=$2
  local expected=$3
  local metadata actual
  metadata=$(GOWORK=off go mod download -json "$module@$version")
  actual=$(printf '%s\n' "$metadata" | jq -r '.Sum')
  if [[ "$actual" != "$expected" ]]; then
    printf 'alternative module checksum mismatch: %s@%s\n' "$module" "$version" >&2
    exit 1
  fi
}

verify_module_sum "$schemagen_module" "$schemagen_version" "$schemagen_sum"
verify_module_sum "$staticcheck_module" "$staticcheck_version" "$staticcheck_sum"
GOBIN="$tools_bin" GOWORK=off go install "$schemagen_module@$schemagen_version"
GOBIN="$tools_bin" GOWORK=off go install "$staticcheck_module/cmd/staticcheck@2026.1"

test "$("$tools_bin/staticcheck" -version)" = 'staticcheck 2026.1 (v0.7.0)'
go version -m "$tools_bin/schemagen" | grep -F $'mod\tgo.opentelemetry.io/collector/cmd/schemagen\tv0.157.0\th1:vVhlz44ZfqHFTneJmT4S9i/QiW0TW8hB6KRqQ9MKcFc=' >/dev/null

collector_archive="$comparison_root/collector.tar.gz"
curl --fail --silent --show-error --location --proto '=https' --tlsv1.2 \
  'https://github.com/open-telemetry/opentelemetry-collector/archive/refs/tags/v0.157.0.tar.gz' \
  --output "$collector_archive"
test "$(sha256sum "$collector_archive" | awk '{print $1}')" = "$collector_archive_sum"
tar -xzf "$collector_archive" -C "$comparison_root"
collector_source="$comparison_root/opentelemetry-collector-0.157.0/cmd/otelcorecol"
grep -Fx 'module go.opentelemetry.io/collector/cmd/otelcorecol' "$collector_source/go.mod" >/dev/null
grep -F 'go.opentelemetry.io/collector/otelcol v0.157.0' "$collector_source/go.mod" >/dev/null
(
  cd "$collector_source"
  GOTOOLCHAIN=local GOWORK=off go build -trimpath -buildvcs=false -o "$tools_bin/otelcorecol" .
)
test "$("$tools_bin/otelcorecol" --version)" = 'otelcorecol version 0.157.0-dev'

cd "$project_root"
GOTOOLCHAIN=local GOPROXY=off GOWORK=off go build -trimpath -buildvcs=false \
  -o "$tools_bin/otelcol-confmap-promotion" ./cmd/otelcol-confmap-promotion

set +e
GOPROXY=off GOWORK=off go vet ./testdata/fixtures/unsafe-anonymous \
  >"$comparison_root/vet.out" 2>&1
vet_status=$?
GOPROXY=off GOWORK=off "$tools_bin/staticcheck" ./testdata/fixtures/unsafe-anonymous \
  >"$comparison_root/staticcheck.out" 2>&1
staticcheck_status=$?
"$tools_bin/otelcol-confmap-promotion" check ./testdata/fixtures/unsafe-anonymous \
  >"$comparison_root/primary.out" 2>&1
primary_status=$?
"$tools_bin/otelcorecol" validate --config="$project_root/testdata/alternatives/otelcorecol-safe.yaml" \
  >"$comparison_root/collector-safe.out" 2>"$comparison_root/collector-safe.err"
collector_safe_status=$?
"$tools_bin/otelcorecol" validate --config="$project_root/testdata/alternatives/otelcorecol-invalid.yaml" \
  >"$comparison_root/collector-invalid.out" 2>"$comparison_root/collector-invalid.err"
collector_invalid_status=$?
set -e

test "$vet_status" -eq 0
test ! -s "$comparison_root/vet.out"
test "$staticcheck_status" -eq 0
test ! -s "$comparison_root/staticcheck.out"
test "$primary_status" -eq 1
grep -F 'OCP001 warning testdata/fixtures/unsafe-anonymous/fixture.go:' "$comparison_root/primary.out" >/dev/null
grep -F 'Config promotes Helper.Unmarshal; sibling fields: encoding' "$comparison_root/primary.out" >/dev/null
test "$collector_safe_status" -eq 0
test ! -s "$comparison_root/collector-safe.err"
test "$collector_invalid_status" -eq 1
grep -F "'struct {}' has invalid keys: encoding" "$comparison_root/collector-invalid.err" >/dev/null
if grep -Eq 'Helper\.Unmarshal|unsafe-anonymous/fixture\.go' "$comparison_root/collector-invalid.err"; then
  echo 'otelcorecol unexpectedly reported source ownership' >&2
  exit 1
fi

schema_root="$comparison_root/schema"
mkdir -p "$schema_root"
GOPROXY=off GOWORK=off "$tools_bin/schemagen" -m package -t json -o "$schema_root" \
  ./testdata/fixtures/unsafe-anonymous >"$comparison_root/schemagen.out" 2>"$comparison_root/schemagen.err"
test ! -s "$comparison_root/schemagen.err"
jq -e '
  .["$defs"].config.properties.encoding.type == "string" and
  (.["$defs"].config.properties | has("queue_size") | not) and
  .["$defs"].helper.properties.queue_size.type == "integer"
' "$schema_root/config.schema.json" >/dev/null

jq -n \
  --arg collectorVersion '0.157.0-dev' \
  --arg schemagenVersion 'v0.157.0' \
  --arg staticcheckVersion '2026.1 (v0.7.0)' \
  '{
    schemaVersion: 1,
    primary: {exit: 1, rule: "OCP001", owner: "Helper.Unmarshal", sibling: "encoding", location: true},
    alternatives: {
      otelcorecol: {version: $collectorVersion, safeExit: 0, invalidExit: 1, reportsInvalidKey: true, reportsSourceOwner: false},
      goVet: {go: "1.26.5", exit: 0, reportsPromotionRisk: false},
      staticcheck: {version: $staticcheckVersion, exit: 0, reportsPromotionRisk: false},
      schemagen: {version: $schemagenVersion, exit: 0, configProperties: ["encoding"], reportsOmittedEmbeddedField: false}
    }
  }'
