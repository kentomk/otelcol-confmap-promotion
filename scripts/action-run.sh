#!/usr/bin/env bash
set -euo pipefail

binary=${INPUT_BINARY:-}
route=${INPUT_ROUTE:-cli}
format=${INPUT_FORMAT:-text}
include_tests=${INPUT_TESTS:-false}
package_lines=${INPUT_PACKAGES:-./...}

if [[ -z "$binary" || ! -x "$binary" ]]; then
  echo 'action failed: binary must name an executable supplied by the caller' >&2
  exit 2
fi
if [[ "$route" != cli && "$route" != vet ]]; then
  echo 'action failed: route must be cli or vet' >&2
  exit 2
fi
if [[ "$format" != text && "$format" != json && "$format" != sarif ]]; then
  echo 'action failed: format must be text, json, or sarif' >&2
  exit 2
fi
if [[ "$include_tests" != true && "$include_tests" != false ]]; then
  echo 'action failed: tests must be true or false' >&2
  exit 2
fi

packages=()
while IFS= read -r package; do
  package=${package%$'\r'}
  if [[ -n "$package" ]]; then
    packages+=("$package")
  fi
done <<< "$package_lines"
if (( ${#packages[@]} == 0 )); then
  echo 'action failed: packages must contain at least one non-empty pattern' >&2
  exit 2
fi

if [[ "$route" == vet ]]; then
  if [[ "$format" != text ]]; then
    echo 'action failed: vet route supports text output only' >&2
    exit 2
  fi
  GOPROXY=off go vet -vettool="$binary" "${packages[@]}"
  exit $?
fi

arguments=(check --format "$format")
if [[ "$include_tests" == true ]]; then
  arguments+=(--tests)
fi
arguments+=("${packages[@]}")
"$binary" "${arguments[@]}"
