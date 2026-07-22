#!/usr/bin/env bash
set -euo pipefail

project_root=$(cd -- "$(dirname -- "$0")/.." && pwd)
fixture_root="$project_root/testdata/agent-selection"
catalog="$fixture_root/catalog.json"
tasks="$fixture_root/tasks.json"
evaluation="$fixture_root/evaluation.json"
replay_root=$(mktemp -d)
trap 'rm -rf -- "$replay_root"' EXIT

if [[ $# -gt 1 ]]; then
  echo 'usage: scripts/agent-selection-evaluation.sh [ALTERNATIVES_RESULT_JSON]' >&2
  exit 2
fi

for document in "$catalog" "$tasks" "$evaluation"; do
  jq -e '.schemaVersion == 1' "$document" >/dev/null
done

catalog_hash=$(sha256sum "$catalog" | awk '{print $1}')
test "$(jq -r '.catalogSha256' "$evaluation")" = "$catalog_hash"
test "$(jq '.routes | length' "$catalog")" -eq 4
test "$(jq '.tasks | length' "$tasks")" -eq 12
test "$(jq '[.tasks[] | select(.class == "target-fit")] | length' "$tasks")" -eq 6
test "$(jq '[.tasks[] | select(.class == "competitor-fit")] | length' "$tasks")" -eq 3
test "$(jq '[.tasks[] | select(.class == "non-goal")] | length' "$tasks")" -eq 3
test "$(jq '[.tasks[].id] | unique | length' "$tasks")" -eq 12
test "$(jq '[.records[].taskId] | unique | length' "$evaluation")" -eq 12

if jq -r '.tasks[].prompt' "$tasks" | grep -Eiq 'otelcol-confmap-promotion|otelcorecol|staticcheck|schemagen|go vet'; then
  echo 'agent selection tasks must not contain project or candidate names' >&2
  exit 1
fi

jq -e --slurpfile decisions "$evaluation" '
  all(.tasks[];
    . as $task |
    ($decisions[0].records | map(select(.taskId == $task.id)) | length) == 1 and
    ($decisions[0].records | map(select(.taskId == $task.id))[0].selectedRoute) == $task.expectedRoute
  )
' "$tasks" >/dev/null
jq -e '
  (.records | length) == 12 and
  all(.records[]; .discover == "passed" and .qualify == "passed" and .taskTest == "passed") and
  ([.records[] | select(.install == "passed")] | length) == 9 and
  ([.records[] | select(.install == "not-applicable")] | length) == 3
' "$evaluation" >/dev/null

cd "$project_root"
install_started=$(date +%s%N)
GOTOOLCHAIN=local GOPROXY=off GOWORK=off go build -trimpath -buildvcs=false \
  -o "$replay_root/otelcol-confmap-promotion" ./cmd/otelcol-confmap-promotion

target_index=0
while IFS=$'\t' read -r task_id fixture parent owner sibling; do
  set +e
  "$replay_root/otelcol-confmap-promotion" check --format json "./$fixture" \
    >"$replay_root/$task_id.json" 2>"$replay_root/$task_id.err"
  status=$?
  set -e
  test "$status" -eq 1
  test ! -s "$replay_root/$task_id.err"
  jq -e --arg parent "$parent" --arg owner "$owner" --arg sibling "$sibling" '
    .summary.diagnostics >= 1 and
    any(.diagnostics[];
      .ruleId == "OCP001" and
      .parentType == $parent and
      .methodOwner == $owner and
      (.siblings | index($sibling)) != null and
      (.location | startswith("testdata/fixtures/"))
    )
  ' "$replay_root/$task_id.json" >/dev/null
  if [[ "$target_index" -eq 0 ]]; then
    first_output_ns=$(date +%s%N)
  fi
  target_index=$((target_index + 1))
done < <(jq -r '.tasks[] | select(.class == "target-fit") | [.id,.fixture,.expectedParent,.expectedOwner,.expectedSibling] | @tsv' "$tasks")
test "$target_index" -eq 6

if [[ $# -eq 1 ]]; then
  alternatives_result=$1
else
  alternatives_result="$replay_root/alternatives.json"
  "$project_root/scripts/alternatives-comparison.sh" >"$alternatives_result"
fi
jq -e '
  .alternatives.otelcorecol.safeExit == 0 and
  .alternatives.otelcorecol.invalidExit == 1 and
  .alternatives.otelcorecol.reportsSourceOwner == false and
  .alternatives.goVet.exit == 0 and
  .alternatives.staticcheck.exit == 0 and
  .alternatives.schemagen.exit == 0 and
  .alternatives.schemagen.configProperties == ["encoding"]
 ' "$alternatives_result" >/dev/null

finished_ns=$(date +%s%N)
first_useful_ms=$(((first_output_ns - install_started) / 1000000))
total_ms=$(((finished_ns - install_started) / 1000000))
test "$first_useful_ms" -le 300000
test "$total_ms" -le 300000

jq -n \
  --arg catalogSha256 "$catalog_hash" \
  --argjson firstUsefulOutputMs "$first_useful_ms" \
  --argjson totalReplayMs "$total_ms" \
  '{
    schemaVersion: 1,
    catalogSha256: $catalogSha256,
    taskMix: {targetFit: 6, competitorFit: 3, nonGoal: 3},
    funnel: {
      discovered: 12,
      discoveryRate: 1,
      selectedCorrectly: 12,
      finalSelectionRate: 1,
      installEligible: 9,
      installSucceeded: 9,
      installSuccessRate: 1,
      taskTestsPassed: 12,
      taskTestPassRate: 1
    },
    execution: {
      firstUsefulOutputMs: $firstUsefulOutputMs,
      totalReplayMs: $totalReplayMs,
      topLevelCommandCount: 8,
      manualInterventions: 0,
      budgetSecondsPerTask: 300
    },
    caveat: "Single automated evaluator over a supplied local catalog; not external adoption or a general model benchmark."
  }'
