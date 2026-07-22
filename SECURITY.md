# Security policy

## Supported versions

The project is not published yet. Security fixes target the current development branch.

## Reporting

Do not put private source, source snippets, comments, literals, absolute paths, module proxy settings, tokens, or environment values in a public report. A private reporting route is not available yet; use an original minimal reproducer with neutral identifiers.

## Security boundary

`otelcol-confmap-promotion` parses and type-checks local Go packages. It does not execute package initialization, run a Collector, contact a package proxy, collect telemetry, or use credentials. Package loading runs with `GOPROXY=off`, so required dependencies must already be available locally.

The active module root and compiled source paths are resolved before analysis. Packages without the active module, module roots outside it, and symlink-resolved source outside it fail closed. Package, type, field, diagnostic, and 60-second wall-time limits are enforced; users may lower but not raise the documented maxima.

Reports include package/type/field identifiers and repository-relative locations. They omit source bodies, comments, literals, environment values, and absolute paths. Treat identifier disclosure, path escape, unexpected dependency download, unbounded package loading, or execution of analyzed code as security bugs.

The analyzer is not a sandbox and does not prove that an explicit parent decoder preserves every field. `--tests` recognizes a narrowly named preservation-test candidate but does not run it or mark the decoder safe. Run the analyzer in a credential-free CI job when analyzing untrusted contributions.

External `_test` package declarations are identified through Go package metadata and emitted as unknown rather than production findings by the CLI; the standard vettool route omits those external-only declarations from actionable diagnostics. Source beneath a `vendor` path segment is rejected; scan the owning first-party package instead. The composite Action accepts only a caller-supplied executable, converts newline-delimited package patterns to literal arguments without evaluation, and uses `GOPROXY=off` on the vet route. Verify the binary checksum before the Action step and do not give the analysis job credentials.

The five-version runtime comparison is separate from analyzer execution. It contacts the configured Go module proxy, verifies hard-coded direct-module checksums plus Go's module sums, runs only the repository's original fixture in a temporary directory, and removes that directory on exit. Do not run this optional comparison in a credential-bearing job; it is not needed by the CLI or vettool.

The pinned alternatives comparison is also maintainer-only and networked. It verifies the direct Go module sums for schemagen and Staticcheck and the SHA-256 of the official Collector v0.157.0 source archive before temporary source builds. It runs only repository-owned source and YAML fixtures, removes the temporary toolchain and outputs on exit, and does not add Collector or Staticcheck modules to the released binaries. Run it without credentials; checksum verification provides provenance comparison, not sandboxing or a vulnerability guarantee.

The agent-selection fixture contains only original neutral task text, public route metadata, and deterministic local commands. It does not send prompts, source, results, or identifiers to a model or external evaluation service during replay. The recorded choices came from one automated AI evaluator and are explicitly unsuitable as a general model, discovery-ranking, safety, or adoption claim.

Release packaging builds the CLI and vettool with `CGO_ENABLED=0`, local pre-verified Go modules, trimmed paths, disabled VCS stamping, and an empty build ID. Archives normalize member order, owner, mode, mtime, and gzip headers; `SHA256SUMS` covers all four platform archives. Verify the checksum before extraction. Reproducibility improves provenance comparison but is not a signature or a guarantee that the source is vulnerability-free.

The static policy gate fails when the embedded runtime module set or version differs from `policy/runtime-dependencies.tsv`, a module's approved BSD-3-Clause license text hash changes, a workflow Action is not pinned to a full commit SHA, or a tracked text file matches a bounded credential/private-key pattern. It also requires official `govulncheck` v1.6.0 and queries the canonical Go vulnerability database for reachable known vulnerabilities. This networked maintainer check sends module paths under the Go database privacy contract; it does not upload source. A clean result covers the database snapshot and supported static-analysis paths only.
