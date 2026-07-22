package main

import (
	"bytes"
	"encoding/json"
	"os"
	"path/filepath"
	"strings"
	"testing"
	"time"
)

func TestBuildConstrainedSourceBecomesUnknown(t *testing.T) {
	workingDirectory, err := os.Getwd()
	if err != nil {
		t.Fatal(err)
	}
	t.Chdir(filepath.Clean(filepath.Join(workingDirectory, "../..")))
	result, err := scan([]string{"./testdata/fixtures/build-tag"}, false, 256)
	if err != nil {
		t.Fatal(err)
	}
	if len(result.Diagnostics) != 0 || len(result.Unknowns) != 1 {
		t.Fatalf("diagnostics=%d unknowns=%d", len(result.Diagnostics), len(result.Unknowns))
	}
	unknown := result.Unknowns[0]
	if unknown.Location != "testdata/fixtures/build-tag/unsafe_windows.go" {
		t.Fatalf("unexpected location: %q", unknown.Location)
	}
	if filepath.IsAbs(unknown.Location) || unknown.Reason == "" {
		t.Fatalf("unsafe unknown: %#v", unknown)
	}
}

func TestSARIFAndLimits(t *testing.T) {
	workingDirectory, err := os.Getwd()
	if err != nil {
		t.Fatal(err)
	}
	t.Chdir(filepath.Clean(filepath.Join(workingDirectory, "../..")))

	result, err := scan([]string{"./testdata/fixtures/unsafe-anonymous"}, false, 256)
	if err != nil {
		t.Fatal(err)
	}
	var output bytes.Buffer
	if err := writeSARIF(&output, result); err != nil {
		t.Fatal(err)
	}
	var decoded map[string]any
	if err := json.Unmarshal(output.Bytes(), &decoded); err != nil {
		t.Fatal(err)
	}
	runs := decoded["runs"].([]any)
	run := runs[0].(map[string]any)
	results := run["results"].([]any)
	first := results[0].(map[string]any)
	if decoded["version"] != "2.1.0" || first["ruleId"] != "OCP001" {
		t.Fatalf("unexpected SARIF: %s", output.String())
	}
	locations := first["locations"].([]any)
	physical := locations[0].(map[string]any)["physicalLocation"].(map[string]any)
	artifact := physical["artifactLocation"].(map[string]any)
	if artifact["uri"] != "testdata/fixtures/unsafe-anonymous/fixture.go" || artifact["uriBaseId"] != "%SRCROOT%" {
		t.Fatalf("unsafe SARIF location: %#v", artifact)
	}

	limits := reportLimits{MaxPackages: 256, MaxTypes: 1, MaxFields: 1000000, MaxDiagnostics: 10000, TimeoutSeconds: 60}
	if _, err := scanWithLimits([]string{"./testdata/fixtures/unsafe-anonymous"}, false, limits, 60*time.Second); err == nil {
		t.Fatal("expected type limit error")
	}
	if _, err := scan([]string{"fmt"}, false, 256); err == nil {
		t.Fatal("expected outside-module error")
	}
}

func TestPreservationEvidenceRemainsUnknown(t *testing.T) {
	workingDirectory, err := os.Getwd()
	if err != nil {
		t.Fatal(err)
	}
	t.Chdir(filepath.Clean(filepath.Join(workingDirectory, "../..")))
	result, err := scan([]string{"./testdata/fixtures/explicit-parent"}, true, 256)
	if err != nil {
		t.Fatal(err)
	}
	if len(result.Diagnostics) != 0 || len(result.Unknowns) != 1 {
		t.Fatalf("diagnostics=%d unknowns=%d", len(result.Diagnostics), len(result.Unknowns))
	}
	if !strings.Contains(result.Unknowns[0].Reason, "candidate names all fields") {
		t.Fatalf("preservation candidate not recognized: %#v", result.Unknowns[0])
	}
}

func TestExternalTestPackageAndVendorBoundary(t *testing.T) {
	workingDirectory, err := os.Getwd()
	if err != nil {
		t.Fatal(err)
	}
	root := filepath.Clean(filepath.Join(workingDirectory, "../.."))
	t.Chdir(root)

	result, err := scan([]string{"./testdata/fixtures/external-test-boundary"}, true, 256)
	if err != nil {
		t.Fatal(err)
	}
	if len(result.Diagnostics) != 0 || len(result.Unknowns) != 1 {
		t.Fatalf("diagnostics=%d unknowns=%d", len(result.Diagnostics), len(result.Unknowns))
	}
	if result.Unknowns[0].Location != "testdata/fixtures/external-test-boundary/fixture_test.go" ||
		!strings.Contains(result.Unknowns[0].Reason, "external test package") {
		t.Fatalf("unexpected external test boundary: %#v", result.Unknowns[0])
	}

	if !isVendoredPath(root, filepath.Join(root, "vendor/example.com/helper/fixture.go")) ||
		!isVendoredPath(root, filepath.Join(root, "nested/vendor/helper/fixture.go")) ||
		isVendoredPath(root, filepath.Join(root, "vendored/helper/fixture.go")) {
		t.Fatal("vendor path boundary is not segment-aware")
	}
}
