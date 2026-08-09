package main

import (
	"testing"

	"github.com/kentomk/otelcol-confmap-promotion/internal/analyzer"
)

func TestDedupeKeepsDistinctFindingsAtOneSourceLine(t *testing.T) {
	diagnostics := dedupeDiagnostics([]analyzer.Diagnostic{
		{Package: "example/config", ParentType: "Config", EmbeddedType: "Logging", MethodOwner: "Helper", Mechanism: "promotes", Siblings: []string{"encoding"}, Location: "fixture.go:12", Message: "first"},
		{Package: "example/config", ParentType: "Config", EmbeddedType: "Queue", MethodOwner: "Helper", Mechanism: "squashes", Siblings: []string{"encoding"}, Location: "fixture.go:12", Message: "second"},
		{Package: "example/config", ParentType: "Config", EmbeddedType: "Logging", MethodOwner: "Helper", Mechanism: "promotes", Siblings: []string{"encoding"}, Location: "fixture.go:12", Message: "first"},
	})
	if len(diagnostics) != 2 {
		t.Fatalf("deduped findings=%d, want 2: %#v", len(diagnostics), diagnostics)
	}
	if diagnostics[0].EmbeddedType != "Logging" || diagnostics[1].EmbeddedType != "Queue" {
		t.Fatalf("order=%q,%q, want Logging,Queue", diagnostics[0].EmbeddedType, diagnostics[1].EmbeddedType)
	}
}

func TestDedupeKeepsDistinctUnknownsAtOneSourceLine(t *testing.T) {
	unknowns := dedupeUnknowns([]analyzer.Unknown{
		{Package: "example/config", ParentType: "Config", EmbeddedType: "Logging", MethodOwner: "Helper", Location: "fixture.go:12", Reason: "generated"},
		{Package: "example/config", ParentType: "Config", EmbeddedType: "Queue", MethodOwner: "Helper", Location: "fixture.go:12", Reason: "explicit decoder"},
	})
	if len(unknowns) != 2 {
		t.Fatalf("deduped unknowns=%d, want 2: %#v", len(unknowns), unknowns)
	}
}
