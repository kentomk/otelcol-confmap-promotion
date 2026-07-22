package main

import (
	"context"
	"encoding/json"
	"errors"
	"flag"
	"fmt"
	"go/ast"
	"os"
	"path/filepath"
	"sort"
	"strings"
	"time"

	"github.com/kentomk/otelcol-confmap-promotion/internal/analyzer"
	"golang.org/x/tools/go/packages"
)

var version = "dev"

type report struct {
	SchemaVersion int                   `json:"schemaVersion"`
	ToolVersion   string                `json:"toolVersion"`
	Packages      []string              `json:"packages"`
	Diagnostics   []analyzer.Diagnostic `json:"diagnostics"`
	Unknowns      []analyzer.Unknown    `json:"unknowns"`
	Summary       summary               `json:"summary"`
	Limits        reportLimits          `json:"limits"`
}

type reportLimits struct {
	MaxPackages    int `json:"maxPackages"`
	MaxTypes       int `json:"maxTypes"`
	MaxFields      int `json:"maxFields"`
	MaxDiagnostics int `json:"maxDiagnostics"`
	TimeoutSeconds int `json:"timeoutSeconds"`
}

type summary struct {
	Packages    int `json:"packages"`
	Diagnostics int `json:"diagnostics"`
	Unknowns    int `json:"unknowns"`
}

func main() {
	os.Exit(run(os.Args[1:]))
}

func run(arguments []string) int {
	if len(arguments) == 1 && arguments[0] == "version" {
		fmt.Println(version)
		return 0
	}
	if len(arguments) == 0 || arguments[0] != "check" {
		fmt.Fprintln(os.Stderr, "usage: otelcol-confmap-promotion check [--format text|json] [PACKAGE...] | version")
		return 2
	}
	flags := flag.NewFlagSet("check", flag.ContinueOnError)
	flags.SetOutput(os.Stderr)
	format := flags.String("format", "text", "text, json, or sarif")
	includeTests := flags.Bool("tests", false, "include test packages")
	maxPackages := flags.Int("max-packages", 256, "maximum loaded packages")
	maxTypes := flags.Int("max-types", 100000, "maximum named types per package")
	maxFields := flags.Int("max-fields", 1000000, "maximum struct fields per package")
	maxDiagnostics := flags.Int("max-diagnostics", 10000, "maximum diagnostics per package")
	timeout := flags.Duration("timeout", 60*time.Second, "analysis timeout")
	if err := flags.Parse(arguments[1:]); err != nil {
		return 2
	}
	if *format != "text" && *format != "json" && *format != "sarif" {
		fmt.Fprintln(os.Stderr, "format must be text, json, or sarif")
		return 2
	}
	if *maxPackages < 1 || *maxPackages > 256 {
		fmt.Fprintln(os.Stderr, "max-packages must be between 1 and 256")
		return 2
	}
	if *maxTypes < 1 || *maxTypes > 100000 || *maxFields < 1 || *maxFields > 1000000 || *maxDiagnostics < 1 || *maxDiagnostics > 10000 {
		fmt.Fprintln(os.Stderr, "type, field, or diagnostic limit is outside its supported range")
		return 2
	}
	if *timeout < time.Second || *timeout > 60*time.Second {
		fmt.Fprintln(os.Stderr, "timeout must be between 1s and 60s")
		return 2
	}
	patterns := flags.Args()
	if len(patterns) == 0 {
		patterns = []string{"./..."}
	}
	limits := reportLimits{MaxPackages: *maxPackages, MaxTypes: *maxTypes, MaxFields: *maxFields, MaxDiagnostics: *maxDiagnostics, TimeoutSeconds: int(timeout.Seconds())}
	result, err := scanWithLimits(patterns, *includeTests, limits, *timeout)
	if err != nil {
		fmt.Fprintf(os.Stderr, "analysis failed: %v\n", err)
		return 2
	}
	if *format == "json" {
		encoder := json.NewEncoder(os.Stdout)
		encoder.SetEscapeHTML(false)
		if err := encoder.Encode(result); err != nil {
			fmt.Fprintln(os.Stderr, "analysis failed: could not encode report")
			return 2
		}
	} else if *format == "sarif" {
		if err := writeSARIF(os.Stdout, result); err != nil {
			fmt.Fprintln(os.Stderr, "analysis failed: could not encode SARIF report")
			return 2
		}
	} else {
		writeText(result)
	}
	if len(result.Diagnostics) > 0 {
		return 1
	}
	return 0
}

func scan(patterns []string, includeTests bool, maxPackages int) (report, error) {
	limits := reportLimits{MaxPackages: maxPackages, MaxTypes: 100000, MaxFields: 1000000, MaxDiagnostics: 10000, TimeoutSeconds: 60}
	return scanWithLimits(patterns, includeTests, limits, 60*time.Second)
}

func scanWithLimits(patterns []string, includeTests bool, limits reportLimits, timeout time.Duration) (report, error) {
	workingDirectory, err := os.Getwd()
	if err != nil {
		return report{}, errors.New("could not determine working directory")
	}
	moduleRoot, err := findModuleRoot(workingDirectory)
	if err != nil {
		return report{}, err
	}
	canonicalRoot, err := filepath.EvalSymlinks(moduleRoot)
	if err != nil {
		return report{}, errors.New("could not resolve module root")
	}
	ctx, cancel := context.WithTimeout(context.Background(), timeout)
	defer cancel()
	configuration := &packages.Config{
		Mode: packages.NeedName | packages.NeedFiles | packages.NeedCompiledGoFiles | packages.NeedSyntax |
			packages.NeedTypes | packages.NeedTypesInfo | packages.NeedTypesSizes | packages.NeedModule | packages.NeedForTest,
		Dir: workingDirectory, Tests: includeTests, Context: ctx,
		Env: append(os.Environ(), "GOPROXY=off"),
	}
	loaded, err := packages.Load(configuration, patterns...)
	if err != nil {
		return report{}, errors.New("package loading did not complete")
	}
	if len(loaded) == 0 {
		return report{}, errors.New("no packages matched")
	}
	if len(loaded) > limits.MaxPackages {
		return report{}, fmt.Errorf("package limit exceeded: %d > %d", len(loaded), limits.MaxPackages)
	}
	output := report{SchemaVersion: 1, ToolVersion: version, Packages: []string{}, Diagnostics: []analyzer.Diagnostic{}, Unknowns: []analyzer.Unknown{}, Limits: limits}
	for _, loadedPackage := range loaded {
		if strings.HasSuffix(loadedPackage.PkgPath, ".test") {
			continue
		}
		if len(loadedPackage.Errors) > 0 || loadedPackage.Types == nil || loadedPackage.Fset == nil {
			return report{}, fmt.Errorf("package %q has load or type errors", safePackageName(loadedPackage.PkgPath))
		}
		if loadedPackage.Module == nil || loadedPackage.Module.Dir == "" {
			return report{}, fmt.Errorf("package %q is outside the active module", safePackageName(loadedPackage.PkgPath))
		}
		packageRoot, err := filepath.EvalSymlinks(loadedPackage.Module.Dir)
		if err != nil || filepath.Clean(packageRoot) != filepath.Clean(canonicalRoot) {
			return report{}, fmt.Errorf("package %q is outside the active module", safePackageName(loadedPackage.PkgPath))
		}
		for _, filename := range loadedPackage.CompiledGoFiles {
			resolved, resolveErr := filepath.EvalSymlinks(filename)
			if resolveErr != nil || !pathWithin(canonicalRoot, resolved) {
				return report{}, fmt.Errorf("package %q contains a source path outside the active module", safePackageName(loadedPackage.PkgPath))
			}
			if isVendoredPath(canonicalRoot, resolved) {
				return report{}, fmt.Errorf("package %q contains vendored source and is not analyzed", safePackageName(loadedPackage.PkgPath))
			}
		}
		if loadedPackage.ForTest != "" && loadedPackage.PkgPath != loadedPackage.ForTest {
			location := "external-test-package"
			for _, filename := range loadedPackage.CompiledGoFiles {
				if strings.HasSuffix(filename, "_test.go") {
					location = safeRelativePath(canonicalRoot, filename)
					break
				}
			}
			output.Packages = append(output.Packages, safePackageName(loadedPackage.PkgPath))
			output.Unknowns = append(output.Unknowns, analyzer.Unknown{
				Package: safePackageName(loadedPackage.PkgPath), Location: location,
				Reason: "external test package declarations are not production config and were not analyzed",
			})
			continue
		}
		files := make([]*ast.File, len(loadedPackage.Syntax))
		copy(files, loadedPackage.Syntax)
		packageResult, scanErr := analyzer.ScanWithLimits(loadedPackage.Fset, loadedPackage.Types, files, canonicalRoot, analyzer.Limits{
			MaxTypes: limits.MaxTypes, MaxFields: limits.MaxFields, MaxDiagnostics: limits.MaxDiagnostics,
		})
		if scanErr != nil {
			return report{}, fmt.Errorf("package %q: %w", safePackageName(loadedPackage.PkgPath), scanErr)
		}
		for _, ignored := range loadedPackage.IgnoredFiles {
			if filepath.Ext(ignored) != ".go" {
				continue
			}
			packageResult.Unknowns = append(packageResult.Unknowns, analyzer.Unknown{
				Package:  safePackageName(loadedPackage.PkgPath),
				Location: safeRelativePath(canonicalRoot, ignored),
				Reason:   "build-constrained Go source was not analyzed for the active target",
			})
		}
		output.Packages = append(output.Packages, safePackageName(loadedPackage.PkgPath))
		output.Diagnostics = append(output.Diagnostics, packageResult.Diagnostics...)
		output.Unknowns = append(output.Unknowns, packageResult.Unknowns...)
	}
	output.Packages = uniqueStrings(output.Packages)
	sort.Slice(output.Diagnostics, func(i, j int) bool {
		return output.Diagnostics[i].Location+output.Diagnostics[i].ParentType < output.Diagnostics[j].Location+output.Diagnostics[j].ParentType
	})
	sort.Slice(output.Unknowns, func(i, j int) bool {
		return output.Unknowns[i].Location+output.Unknowns[i].ParentType < output.Unknowns[j].Location+output.Unknowns[j].ParentType
	})
	output.Summary = summary{Packages: len(output.Packages), Diagnostics: len(output.Diagnostics), Unknowns: len(output.Unknowns)}
	output.Unknowns = dedupeUnknowns(output.Unknowns)
	output.Diagnostics = dedupeDiagnostics(output.Diagnostics)
	output.Summary = summary{Packages: len(output.Packages), Diagnostics: len(output.Diagnostics), Unknowns: len(output.Unknowns)}
	return output, nil
}

func writeText(output report) {
	for _, diagnostic := range output.Diagnostics {
		fmt.Printf("%s %s %s: %s\n", diagnostic.RuleID, diagnostic.Severity, diagnostic.Location, diagnostic.Message)
	}
	for _, unknown := range output.Unknowns {
		if unknown.ParentType == "" {
			fmt.Printf("UNKNOWN note %s: %s\n", unknown.Location, unknown.Reason)
			continue
		}
		fmt.Printf("UNKNOWN note %s: %s embeds %s.%s; %s\n", unknown.Location, unknown.ParentType, unknown.MethodOwner, "Unmarshal", unknown.Reason)
	}
	fmt.Printf("summary: packages=%d diagnostics=%d unknowns=%d\n", output.Summary.Packages, output.Summary.Diagnostics, output.Summary.Unknowns)
}

func safePackageName(value string) string {
	value = filepath.ToSlash(value)
	if strings.Contains(value, "@") {
		return "external-package"
	}
	return value
}

func safeRelativePath(root, value string) string {
	cleaned := filepath.Clean(value)
	relative, err := filepath.Rel(root, cleaned)
	if err != nil || relative == ".." || strings.HasPrefix(relative, ".."+string(filepath.Separator)) {
		return filepath.Base(cleaned)
	}
	return filepath.ToSlash(relative)
}

func findModuleRoot(start string) (string, error) {
	directory := filepath.Clean(start)
	for {
		if information, err := os.Stat(filepath.Join(directory, "go.mod")); err == nil && !information.IsDir() {
			return directory, nil
		}
		parent := filepath.Dir(directory)
		if parent == directory {
			return "", errors.New("could not find active go.mod")
		}
		directory = parent
	}
}

func pathWithin(root, value string) bool {
	relative, err := filepath.Rel(root, value)
	return err == nil && relative != ".." && !strings.HasPrefix(relative, ".."+string(filepath.Separator))
}

func isVendoredPath(root, value string) bool {
	relative, err := filepath.Rel(root, value)
	if err != nil {
		return false
	}
	for _, part := range strings.Split(filepath.ToSlash(relative), "/") {
		if part == "vendor" {
			return true
		}
	}
	return false
}

func uniqueStrings(values []string) []string {
	sort.Strings(values)
	output := values[:0]
	for _, value := range values {
		if len(output) == 0 || output[len(output)-1] != value {
			output = append(output, value)
		}
	}
	return output
}

func dedupeDiagnostics(values []analyzer.Diagnostic) []analyzer.Diagnostic {
	output := values[:0]
	seen := make(map[string]bool)
	for _, value := range values {
		key := value.Location + "\x00" + value.ParentType + "\x00" + value.MethodOwner
		if !seen[key] {
			seen[key] = true
			output = append(output, value)
		}
	}
	return output
}

func dedupeUnknowns(values []analyzer.Unknown) []analyzer.Unknown {
	byKey := make(map[string]analyzer.Unknown)
	for _, value := range values {
		key := value.Location + "\x00" + value.ParentType + "\x00" + value.MethodOwner
		current, exists := byKey[key]
		if !exists || strings.Contains(value.Reason, "candidate names all fields") {
			byKey[key] = value
		} else {
			byKey[key] = current
		}
	}
	output := make([]analyzer.Unknown, 0, len(byKey))
	for _, value := range byKey {
		output = append(output, value)
	}
	sort.Slice(output, func(i, j int) bool {
		return output[i].Location+output[i].ParentType < output[j].Location+output[j].ParentType
	})
	return output
}
