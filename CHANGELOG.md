# Changelog

All notable changes will be documented here. The project follows Semantic Versioning after its first public release.

## Unreleased

- Make top-level and `check --help` discoverable, complete, and successful without loading a package; cover text, JSON, SARIF, limits, tests, and timeout options in the tested usage contract.
- Select caller `CC`, platform `cc`, or installed Zig for ordinary race tests, install exact non-Go quality-gate tools in CI, and keep the verified publisher gate on Zig 0.16.0.
- Add a Linux arm64 publisher entrypoint that verifies exact toolchains and resolves the pinned vulnerability scanner independently of the login-shell `PATH`.
- Add a publisher smoke command that runs the full quality gate and fails closed on missing tracked test paths, required README metadata, or oversized repository payloads.
- Add the initial network-free source analyzer with deterministic text and JSON output.
- Detect direct anonymous promotion of `Unmarshal(*confmap.Conf) error` with parent siblings as `OCP001`.
- Classify an explicit parent decoder as unknown instead of an actionable diagnostic.
- Add original unsafe, nested-safe, and explicit-parent fixtures and a 60-second quick start.
- Resolve value and pointer receivers through actual Go method sets, including multi-level embedding, aliases, and generic instantiations.
- Detect named `mapstructure` and `confmap` squash fields.
- Classify generated types and inactive build-constrained Go files as unknown instead of silently passing them.
- Add SARIF 2.1.0 output with `%SRCROOT%` locations and unknown/limit run properties.
- Fail closed on package, type, field, diagnostic, timeout, symlink-resolved source, and outside-module boundaries.
- Recognize explicit sibling-preservation test candidates without treating them as proof of safety.
- Add a dedicated `go vet -vettool` binary backed by the same `OCP001` analyzer.
- Add a checksum-pinned temporary runtime comparison across five confmap versions for rejected, nested-safe, and silent-ignore behavior.
- Separate external test-package declarations into explicit unknowns and reject vendored source analysis.
- Add an offline composite Action for caller-supplied CLI or vettool binaries with literal package arguments and exit propagation smoke tests.
- Add reproducible Linux/macOS amd64/arm64 archives containing versioned CLI and vettool binaries, `SHA256SUMS`, and a repairable release workflow.
- Add fail-closed runtime module/license inventory, official advisory scan, tracked-secret detection, full-SHA workflow policy, and release binary provenance checks.
- Add a checksum-pinned executable comparison against otelcorecol validate, Go vet, Staticcheck, and schemagen that fixes the analyzer's narrow source-ownership gap.
- Add a reproducible 12-task controlled agent-selection fixture that separates discovery, qualification, install, and task/test outcomes without treating the result as adoption.
