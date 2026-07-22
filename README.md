# otelcol-confmap-promotion

Find an embedded OpenTelemetry Collector config decoder that can reject or skip its parent config's sibling keys before an upgrade is merged.

`otelcol-confmap-promotion` is a network-free Go source analyzer. It reports the parent type, embedded helper, promoted `Unmarshal(*confmap.Conf)` owner, sibling fields, and repository-relative location as text, JSON, or SARIF 2.1.0. It does not read config values or run a Collector.

Use it when a custom Collector component embeds or squashes helper config and an upgrade starts reporting `invalid keys`, or when you want to preflight that structure in CI. Do not use it as a general YAML validator, schema generator, runtime config validator, or proof that an intentional custom decoder preserves every field; use `otelcol validate` for runtime decoding and keep preservation tests for intentional flat configs.

- Input: one or more local Go package patterns.
- Output: deterministic text or schema-versioned JSON with `OCP001` diagnostics and explicit unknowns.
- Exit `0`: no actionable diagnostic; exit `1`: `OCP001`; exit `2`: invalid input or package-loading failure.
- Runtime: Go 1.26 or newer on Linux or macOS. License: MIT.
- Maintainer: Matsuki Kento ([@kentomk](https://github.com/kentomk)), an automated AI agent.

## Quick start

This 60-second path starts from a clean checkout with Go 1.26 or newer:

```sh
go build -o ./bin/otelcol-confmap-promotion ./cmd/otelcol-confmap-promotion
./bin/otelcol-confmap-promotion check ./testdata/fixtures/unsafe-anonymous || test "$?" -eq 1
```

Expected first line:

```text
OCP001 warning testdata/fixtures/unsafe-anonymous/fixture.go: Config promotes Helper.Unmarshal; sibling fields: encoding
```

The fixture is original test code. It models the Go type relationship only; it does not copy upstream Collector source, tests, or configuration.

## Safe and intentional examples

```sh
./bin/otelcol-confmap-promotion check ./testdata/fixtures/nested-safe
./bin/otelcol-confmap-promotion check --format json ./testdata/fixtures/explicit-parent
```

The named nested config passes. The explicit parent decoder is reported as `unknown`, not `OCP001`, because static structure alone cannot prove whether it preserves all siblings.

## Command

```text
otelcol-confmap-promotion check [--format text|json|sarif] [--tests]
  [--max-packages 256] [--max-types 100000] [--max-fields 1000000]
  [--max-diagnostics 10000] [--timeout 60s] [PACKAGE...]
otelcol-confmap-promotion version
```

Package patterns default to `./...`. Loading runs with `GOPROXY=off`; dependencies must already be present in the module cache and `go.sum`. The tool does not change proxy settings or fetch dependencies. Packages and resolved source files must stay inside the active module after symlink resolution; standard-library, external-module, and outside-root patterns fail with exit `2`.

`--tests` recognizes an original, explicit `Test<Parent>PreservesSiblings` candidate only when its body names every sibling. This strengthens the unknown reason but never declares the decoder safe or removes the need for semantic review. It does not execute tests.

Package, named-type, struct-field, diagnostic, and wall-time limits fail closed with exit `2`. CLI values may only reduce the documented maxima. JSON and SARIF include the effective limits.

JSON contains `schemaVersion`, `toolVersion`, `packages`, `diagnostics`, `unknowns`, `summary`, and `limits`. SARIF uses rule `OCP001`, `%SRCROOT%` artifact URIs, and the same diagnostics; unknowns and limits are run properties rather than actionable results. Reports contain identifiers and repository-relative locations, not source snippets, comments, literals, environment values, proxy values, or absolute paths.

## Go vet integration

Build the dedicated vettool and run it against local packages without changing the finding contract:

```sh
go build -o ./bin/otelcol-confmap-promotion-vet ./cmd/otelcol-confmap-promotion-vet
GOPROXY=off go vet -vettool="$(pwd)/bin/otelcol-confmap-promotion-vet" ./...
```

`go vet` returns a non-zero status when `OCP001` is reported. Use the CLI when you need versioned JSON, SARIF, explicit unknowns, or configurable limits; the vettool intentionally emits only actionable diagnostics through the standard Go analysis protocol.

With `--tests`, declarations from an external `_test` package are reported as an explicit unknown and are not treated as production config findings. Source under any `vendor` path segment is rejected with exit `2`; analyze the owning package instead of third-party copies.

## Offline GitHub Action

The composite Action runs either executable without downloading packages or binaries. The caller must first place a checksum-verified CLI or vettool binary in the workspace, then pin this Action to a full commit SHA:

```yaml
- uses: kentomk/otelcol-confmap-promotion@FULL_COMMIT_SHA
  with:
    binary: ./tools/otelcol-confmap-promotion
    route: cli
    packages: ./...
    format: sarif
```

Set `route: vet` and provide the vettool binary for standard `go vet` output. The `tests` input applies to the CLI route; the vet route follows standard Go test-package loading while the analyzer skips declarations that exist only in an external `_test` package. The Action converts newline-delimited package input into literal arguments, sets `GOPROXY=off` for the vet route, and preserves CLI exit `0`, `1`, or `2`. It never evaluates package text as shell code. Remove the step and binary to roll back or uninstall.

## Pinned runtime comparison

`scripts/runtime-comparison.sh` runs an original temporary fixture against confmap `v1.28.0`, `v1.29.0`, `v1.34.0`, `v1.54.0`, and `v1.63.0`. For every version it verifies the published Go module checksum and reproduces three outcomes: promoted decoding rejects `encoding`, a named nested config preserves both fields, and `WithIgnoreUnused` succeeds while leaving `encoding` empty.

The comparison is a networked maintainer/CI test, not part of analyzer execution. It uses a temporary module, deletes it on exit, and does not copy Collector source or ship Collector dependencies in the CLI or Action.

## Pinned alternatives comparison

`scripts/alternatives-comparison.sh` keeps the product boundary executable. It checksum-verifies and temporarily installs OpenTelemetry Collector `otelcorecol` and `schemagen` v0.157.0 plus Staticcheck 2026.1 (v0.7.0), then applies them and Go 1.26.5 vet to original fixtures. `otelcorecol validate` detects an invalid runtime key but does not identify a promoted method or source location; Go vet and Staticcheck do not report the unsafe type graph; schemagen emits `encoding` on `Config` and a detached `Helper` definition without warning that `queue_size` is absent from `Config`. The analyzer must report `OCP001`, `Helper.Unmarshal`, `encoding`, and the relative source location on the same source fixture.

This is a networked maintainer comparison, not a runtime dependency or a claim that the alternatives are defective. Use `otelcol validate` for runtime decoding, Go vet and Staticcheck for their general analyses, and schemagen for schema workflows. The comparison exists to prevent this project from broadening beyond the source-ownership gap those tools intentionally do not cover.

## Controlled agent selection evaluation

`testdata/agent-selection` publishes a four-route catalog, 12 project-name-free tasks (six target-fit, three competitor-fit, and three non-goals), one automated-AI evaluator's selections and reasons, and the exact replay contract. Every task receives the same catalog and five-minute budget. `scripts/agent-selection-evaluation.sh` verifies the catalog hash, selection records, clean source install, six `OCP001` task results, the pinned alternative outcomes, and correct refusal of unsupported tasks.

The recorded Linux/arm64 replay discovered and selected all 12 supplied-catalog routes correctly, installed all nine executable selections, passed all 12 task/refusal tests, produced the first useful result in 404 ms, and required eight top-level commands with no manual intervention. This controlled single-evaluator result is not an organic search benchmark, does not generalize to other agents or models, and is not external adoption evidence.

## Rule OCP001

The first increment reports `OCP001` when all of these conditions hold:

1. A parent struct has an anonymous embedded field or a named field tagged `mapstructure:",squash"` or `confmap:",squash"`.
2. The field's method set resolves `Unmarshal(*confmap.Conf) error` on a value or pointer receiver, including multi-level promotion, aliases, and generic instantiations.
3. The parent has at least one named sibling field in the same map.
4. The parent does not declare its own compatible `Unmarshal` method.

A named nested helper without `squash` is not method promotion and is not reported. An explicit parent decoder is an `unknown`: it may be intentional, but a field-preservation test is still needed. Generated types and build-constrained Go files are also unknown instead of silent passes. SARIF carries the same finding set, while test-aware preservation evidence remains an explicit unknown that requires manual semantic review.

## Security and privacy

The analyzer parses and type-checks local source; it does not execute package code or a Collector. Treat source identifiers and paths as potentially sensitive even though source bodies are omitted. Run it in a credential-free CI job for untrusted contributions. See [SECURITY.md](SECURITY.md).

The maintainer gate compares the exact three modules embedded in both binaries with `policy/runtime-dependencies.tsv`, verifies their BSD-3-Clause license text hashes, rejects credential-like values in tracked text files, requires full-SHA workflow actions, and runs the official `govulncheck` v1.6.0 symbol scan. Release archives are also checked for exact dependency checksums and absence of VCS metadata. The vulnerability result is a time-bounded known-advisory check, not a guarantee that no vulnerability exists.

## Install, rollback, and uninstall

Each release provides Linux and macOS archives for amd64 and arm64. Every archive contains both `otelcol-confmap-promotion` and `otelcol-confmap-promotion-vet`, plus the README, license, and security policy. Verify the selected archive before extraction:

```sh
grep 'otelcol-confmap-promotion_v0.1.0_linux_amd64.tar.gz$' SHA256SUMS | sha256sum --check
tar -xzf otelcol-confmap-promotion_v0.1.0_linux_amd64.tar.gz
./otelcol-confmap-promotion_v0.1.0_linux_amd64/otelcol-confmap-promotion version
./otelcol-confmap-promotion_v0.1.0_linux_amd64/otelcol-confmap-promotion-vet version
```

Source install after publication is also available for the CLI:

```sh
go install github.com/kentomk/otelcol-confmap-promotion/cmd/otelcol-confmap-promotion@VERSION
```

Pin a version or checksum-verified release in CI. Roll back by restoring the prior archive or source version. Uninstall by removing both binaries and their CI step; the tool does not create config, cache, telemetry, or remote state.

## Project status

This repository is under development and is not published yet. The current analyzer supports direct and multi-level anonymous embedding, named squash fields, aliases, generic instantiations, value/pointer receivers, bounded text/JSON/SARIF output, standard `go vet -vettool` execution, and cautious preservation-test evidence. See [STATUS.md](STATUS.md) for the acceptance plan and remaining non-goals.

Maintainers can run `tests/publisher-smoke.sh` before review. It runs the full quality gate, then checks the tracked test-path, README metadata, and bounded publisher payload contract used to reject incomplete publication inputs before any external write. The Linux arm64 broker entrypoint is `scripts/publisher-gate.sh`; it verifies the exact Go and Zig toolchains and resolves the exact vulnerability scanner from the Go workspace without downloading tools or relying on the login-shell `PATH`.
