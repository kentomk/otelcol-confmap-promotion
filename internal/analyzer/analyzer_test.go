package analyzer_test

import (
	"os"
	"path/filepath"
	"testing"

	"github.com/kentomk/otelcol-confmap-promotion/internal/analyzer"
	"golang.org/x/tools/go/packages"
)

func TestOriginalFixtures(t *testing.T) {
	root := moduleRoot(t)
	tests := []struct {
		name        string
		pattern     string
		diagnostics int
		unknowns    int
		parent      string
		sibling     string
	}{
		{name: "unsafe anonymous", pattern: "./testdata/fixtures/unsafe-anonymous", diagnostics: 1, parent: "Config", sibling: "encoding"},
		{name: "unsafe squash", pattern: "./testdata/fixtures/unsafe-squash", diagnostics: 1, parent: "Config", sibling: "compress_in_memory"},
		{name: "value receiver", pattern: "./testdata/fixtures/value-receiver", diagnostics: 1, parent: "Config", sibling: "encoding"},
		{name: "multi level", pattern: "./testdata/fixtures/multi-level", diagnostics: 1, parent: "Config", sibling: "encoding"},
		{name: "alias", pattern: "./testdata/fixtures/alias", diagnostics: 1, parent: "Config", sibling: "encoding"},
		{name: "generic", pattern: "./testdata/fixtures/generic", diagnostics: 1, parent: "Config", sibling: "encoding"},
		{name: "nested safe", pattern: "./testdata/fixtures/nested-safe", diagnostics: 0, unknowns: 0},
		{name: "no custom unmarshal", pattern: "./testdata/fixtures/no-custom-unmarshal", diagnostics: 0, unknowns: 0},
		{name: "wrong signature", pattern: "./testdata/fixtures/wrong-signature", diagnostics: 0, unknowns: 0},
		{name: "explicit parent", pattern: "./testdata/fixtures/explicit-parent", diagnostics: 0, unknowns: 1, parent: "Config", sibling: "encoding"},
		{name: "generated", pattern: "./testdata/fixtures/generated", diagnostics: 0, unknowns: 1, parent: "Config", sibling: "encoding"},
	}
	for _, test := range tests {
		t.Run(test.name, func(t *testing.T) {
			loaded, err := packages.Load(&packages.Config{
				Mode: packages.NeedName | packages.NeedFiles | packages.NeedCompiledGoFiles | packages.NeedSyntax |
					packages.NeedTypes | packages.NeedTypesInfo | packages.NeedTypesSizes | packages.NeedModule,
				Dir: root, Env: append(os.Environ(), "GOPROXY=off"),
			}, test.pattern)
			if err != nil || len(loaded) != 1 || len(loaded[0].Errors) != 0 {
				t.Fatalf("load fixture: err=%v packages=%d errors=%v", err, len(loaded), packageErrors(loaded))
			}
			result := analyzer.Scan(loaded[0].Fset, loaded[0].Types, loaded[0].Syntax, root)
			if len(result.Diagnostics) != test.diagnostics || len(result.Unknowns) != test.unknowns {
				t.Fatalf("diagnostics=%d unknowns=%d", len(result.Diagnostics), len(result.Unknowns))
			}
			if test.diagnostics == 1 {
				got := result.Diagnostics[0]
				if got.RuleID != analyzer.RuleID || got.ParentType != test.parent || len(got.Siblings) == 0 || got.Siblings[0] != test.sibling {
					t.Fatalf("unexpected diagnostic: %#v", got)
				}
				if filepath.IsAbs(got.Location) {
					t.Fatalf("location must be relative: %q", got.Location)
				}
			}
			if test.unknowns == 1 && result.Unknowns[0].ParentType != test.parent {
				t.Fatalf("unexpected unknown: %#v", result.Unknowns[0])
			}
		})
	}
}

func moduleRoot(t *testing.T) string {
	t.Helper()
	directory, err := os.Getwd()
	if err != nil {
		t.Fatal(err)
	}
	return filepath.Clean(filepath.Join(directory, "../.."))
}

func packageErrors(loaded []*packages.Package) []packages.Error {
	var errors []packages.Error
	for _, loadedPackage := range loaded {
		errors = append(errors, loadedPackage.Errors...)
	}
	return errors
}
