package main

import (
	"fmt"
	"os"

	"github.com/kentomk/otelcol-confmap-promotion/internal/analyzer"
	"golang.org/x/tools/go/analysis/singlechecker"
)

var version = "dev"

func main() {
	if len(os.Args) == 2 && os.Args[1] == "version" {
		fmt.Println(version)
		return
	}
	singlechecker.Main(analyzer.Analyzer)
}
