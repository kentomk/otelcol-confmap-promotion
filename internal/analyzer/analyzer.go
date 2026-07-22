package analyzer

import (
	"errors"
	"fmt"
	"go/ast"
	"go/token"
	"go/types"
	"path/filepath"
	"reflect"
	"sort"
	"strings"

	"golang.org/x/tools/go/analysis"
)

const RuleID = "OCP001"

type Diagnostic struct {
	RuleID       string   `json:"ruleId"`
	Severity     string   `json:"severity"`
	Package      string   `json:"package"`
	ParentType   string   `json:"parentType"`
	EmbeddedType string   `json:"embeddedType"`
	MethodOwner  string   `json:"methodOwner"`
	Mechanism    string   `json:"mechanism"`
	Siblings     []string `json:"siblings"`
	Location     string   `json:"location"`
	Message      string   `json:"message"`
	Remediation  string   `json:"remediation"`
	pos          token.Pos
}

type Unknown struct {
	Package      string   `json:"package"`
	ParentType   string   `json:"parentType"`
	EmbeddedType string   `json:"embeddedType"`
	MethodOwner  string   `json:"methodOwner"`
	Siblings     []string `json:"siblings"`
	Location     string   `json:"location"`
	Reason       string   `json:"reason"`
	pos          token.Pos
}

type Result struct {
	Diagnostics []Diagnostic
	Unknowns    []Unknown
}

type Limits struct {
	MaxTypes       int `json:"maxTypes"`
	MaxFields      int `json:"maxFields"`
	MaxDiagnostics int `json:"maxDiagnostics"`
}

var DefaultLimits = Limits{MaxTypes: 100000, MaxFields: 1000000, MaxDiagnostics: 10000}

var Analyzer = &analysis.Analyzer{
	Name: "otelcolconfmappromotion",
	Doc:  "find promoted confmap decoders that can consume parent sibling keys",
	Run: func(pass *analysis.Pass) (any, error) {
		if isExternalTestPass(pass) {
			return Result{Diagnostics: []Diagnostic{}, Unknowns: []Unknown{}}, nil
		}
		result := Scan(pass.Fset, pass.Pkg, pass.Files, "")
		for _, diagnostic := range result.Diagnostics {
			pass.Reportf(diagnostic.pos, "%s: %s", RuleID, diagnostic.Message)
		}
		return result, nil
	},
}

func isExternalTestPass(pass *analysis.Pass) bool {
	if !strings.HasSuffix(pass.Pkg.Name(), "_test") || len(pass.Files) == 0 {
		return false
	}
	for _, file := range pass.Files {
		if !strings.HasSuffix(pass.Fset.Position(file.Pos()).Filename, "_test.go") {
			return false
		}
	}
	return true
}

func Scan(fset *token.FileSet, pkg *types.Package, files []*ast.File, root string) Result {
	result, _ := ScanWithLimits(fset, pkg, files, root, DefaultLimits)
	return result
}

func ScanWithLimits(fset *token.FileSet, pkg *types.Package, files []*ast.File, root string, limits Limits) (Result, error) {
	result := Result{Diagnostics: []Diagnostic{}, Unknowns: []Unknown{}}
	generated := generatedTypePositions(files)
	names := pkg.Scope().Names()
	sort.Strings(names)
	typeCount := 0
	fieldCount := 0
	for _, name := range names {
		obj, ok := pkg.Scope().Lookup(name).(*types.TypeName)
		if !ok {
			continue
		}
		typeCount++
		if typeCount > limits.MaxTypes {
			return result, errors.New("type limit exceeded")
		}
		parent, ok := obj.Type().(*types.Named)
		if !ok {
			continue
		}
		structure, ok := parent.Underlying().(*types.Struct)
		if !ok {
			continue
		}
		fieldCount += structure.NumFields()
		if fieldCount > limits.MaxFields {
			return result, errors.New("field limit exceeded")
		}
		parentDecoder := declaredConfmapUnmarshal(parent)
		for index := 0; index < structure.NumFields(); index++ {
			field := structure.Field(index)
			mechanism, candidate := fieldMechanism(structure, index)
			if !candidate {
				continue
			}
			helper := baseNamed(field.Type())
			if helper == nil {
				continue
			}
			decoder := confmapUnmarshalInMethodSet(field.Type())
			if decoder == nil {
				continue
			}
			siblings := siblingNames(structure, index)
			if len(siblings) == 0 {
				continue
			}
			location := relativeLocation(fset.Position(field.Pos()), root)
			owner := receiverOwner(decoder)
			if generated[parent.Obj().Pos()] || generated[helper.Obj().Pos()] {
				result.Unknowns = append(result.Unknowns, Unknown{
					Package: pkg.Path(), ParentType: parent.Obj().Name(), EmbeddedType: field.Name(),
					MethodOwner: owner, Siblings: siblings, Location: location,
					Reason: "generated parent or helper source is not classified as actionable",
					pos:    field.Pos(),
				})
				continue
			}
			if parentDecoder != nil {
				reason := "parent declares its own compatible Unmarshal; require a sibling-preservation test"
				if hasPreservationTest(files, parent.Obj().Name(), siblings) {
					reason = "sibling-preservation test candidate names all fields; manual semantic review is still required"
				}
				result.Unknowns = append(result.Unknowns, Unknown{
					Package: pkg.Path(), ParentType: parent.Obj().Name(), EmbeddedType: field.Name(),
					MethodOwner: owner, Siblings: siblings, Location: location,
					Reason: reason,
					pos:    field.Pos(),
				})
				continue
			}
			message := fmt.Sprintf("%s %s %s.Unmarshal; sibling fields: %s", parent.Obj().Name(), mechanism, owner, strings.Join(siblings, ", "))
			result.Diagnostics = append(result.Diagnostics, Diagnostic{
				RuleID: RuleID, Severity: "warning", Package: pkg.Path(), ParentType: parent.Obj().Name(),
				EmbeddedType: field.Name(), MethodOwner: owner, Mechanism: mechanism, Siblings: siblings, Location: location,
				Message: message, Remediation: "prefer a named nested config or add an explicit parent decoder with a sibling-preservation test",
				pos: field.Pos(),
			})
			if len(result.Diagnostics) > limits.MaxDiagnostics {
				return result, errors.New("diagnostic limit exceeded")
			}
		}
	}
	sort.Slice(result.Diagnostics, func(i, j int) bool {
		return result.Diagnostics[i].Location+result.Diagnostics[i].ParentType < result.Diagnostics[j].Location+result.Diagnostics[j].ParentType
	})
	sort.Slice(result.Unknowns, func(i, j int) bool {
		return result.Unknowns[i].Location+result.Unknowns[i].ParentType < result.Unknowns[j].Location+result.Unknowns[j].ParentType
	})
	return result, nil
}

func declaredConfmapUnmarshal(named *types.Named) *types.Func {
	for index := 0; index < named.NumMethods(); index++ {
		method := named.Method(index)
		if method.Name() == "Unmarshal" && isConfmapSignature(method) {
			return method
		}
	}
	return nil
}

func confmapUnmarshalInMethodSet(value types.Type) *types.Func {
	named := baseNamed(value)
	if named == nil {
		return nil
	}
	selection := types.NewMethodSet(types.NewPointer(named)).Lookup(nil, "Unmarshal")
	if selection == nil {
		return nil
	}
	method, ok := selection.Obj().(*types.Func)
	if !ok || !isConfmapSignature(method) {
		return nil
	}
	return method
}

func isConfmapSignature(method *types.Func) bool {
	signature, ok := method.Type().(*types.Signature)
	if !ok || signature.Params().Len() != 1 || signature.Results().Len() != 1 {
		return false
	}
	pointer, ok := signature.Params().At(0).Type().(*types.Pointer)
	if !ok {
		return false
	}
	conf, ok := pointer.Elem().(*types.Named)
	if !ok || conf.Obj().Name() != "Conf" || conf.Obj().Pkg() == nil || conf.Obj().Pkg().Name() != "confmap" {
		return false
	}
	errorType := types.Universe.Lookup("error").Type()
	return types.Identical(signature.Results().At(0).Type(), errorType)
}

func baseNamed(value types.Type) *types.Named {
	value = types.Unalias(value)
	if pointer, ok := value.(*types.Pointer); ok {
		value = types.Unalias(pointer.Elem())
	}
	named, _ := value.(*types.Named)
	return named
}

func receiverOwner(method *types.Func) string {
	signature, ok := method.Type().(*types.Signature)
	if !ok || signature.Recv() == nil {
		return "unknown"
	}
	receiver := baseNamed(signature.Recv().Type())
	if receiver == nil {
		return "unknown"
	}
	return receiver.Obj().Name()
}

func fieldMechanism(structure *types.Struct, index int) (string, bool) {
	field := structure.Field(index)
	if field.Embedded() {
		return "promotes", true
	}
	tag := reflect.StructTag(structure.Tag(index))
	for _, key := range []string{"mapstructure", "confmap"} {
		parts := strings.Split(tag.Get(key), ",")
		for _, option := range parts[1:] {
			if option == "squash" {
				return "squashes", true
			}
		}
	}
	return "", false
}

func generatedTypePositions(files []*ast.File) map[token.Pos]bool {
	positions := make(map[token.Pos]bool)
	for _, file := range files {
		if !ast.IsGenerated(file) {
			continue
		}
		for _, declaration := range file.Decls {
			general, ok := declaration.(*ast.GenDecl)
			if !ok || general.Tok != token.TYPE {
				continue
			}
			for _, specification := range general.Specs {
				if typeSpec, ok := specification.(*ast.TypeSpec); ok {
					positions[typeSpec.Name.Pos()] = true
				}
			}
		}
	}
	return positions
}

func hasPreservationTest(files []*ast.File, parent string, siblings []string) bool {
	wantedName := "Test" + parent + "PreservesSiblings"
	for _, file := range files {
		for _, declaration := range file.Decls {
			function, ok := declaration.(*ast.FuncDecl)
			if !ok || function.Name.Name != wantedName || function.Body == nil {
				continue
			}
			found := make(map[string]bool)
			ast.Inspect(function.Body, func(node ast.Node) bool {
				literal, ok := node.(*ast.BasicLit)
				if !ok || literal.Kind != token.STRING {
					return true
				}
				value := strings.Trim(literal.Value, "`\"")
				found[value] = true
				return true
			})
			all := true
			for _, sibling := range siblings {
				all = all && found[sibling]
			}
			if all {
				return true
			}
		}
	}
	return false
}

func siblingNames(structure *types.Struct, embeddedIndex int) []string {
	var siblings []string
	for index := 0; index < structure.NumFields(); index++ {
		if index == embeddedIndex {
			continue
		}
		field := structure.Field(index)
		if field.Embedded() || !field.Exported() {
			continue
		}
		tag := reflect.StructTag(structure.Tag(index))
		mapName := strings.Split(tag.Get("mapstructure"), ",")[0]
		if mapName == "-" {
			continue
		}
		if mapName == "" {
			mapName = lowerFirst(field.Name())
		}
		siblings = append(siblings, mapName)
	}
	sort.Strings(siblings)
	return siblings
}

func lowerFirst(value string) string {
	if value == "" {
		return value
	}
	return strings.ToLower(value[:1]) + value[1:]
}

func relativeLocation(position token.Position, root string) string {
	filename := filepath.Clean(position.Filename)
	if root != "" {
		if relative, err := filepath.Rel(root, filename); err == nil && relative != ".." && !strings.HasPrefix(relative, ".."+string(filepath.Separator)) {
			filename = relative
		} else {
			filename = filepath.Base(filename)
		}
	} else {
		filename = filepath.Base(filename)
	}
	return filepath.ToSlash(fmt.Sprintf("%s:%d", filename, position.Line))
}
