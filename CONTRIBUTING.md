# Contributing

Thank you for helping make custom Collector upgrade failures easier to diagnose.

Keep contributions limited to Go method promotion of confmap-compatible custom decoders and parent sibling preservation. Do not add a general YAML validator, runtime Collector wrapper, hosted telemetry, source rewriting, or production configuration fixtures.

Every behavior change needs an original minimal fixture and a deterministic text/JSON assertion. Never copy third-party source, tests, fixtures, or configuration. Reports must not include source snippets, comments, literals, absolute paths, environment values, or credentials.

Run before submitting a change:

```sh
gofmt -w .
scripts/quality-gate.sh
```

By contributing, you agree that your contribution is licensed under the MIT License.
