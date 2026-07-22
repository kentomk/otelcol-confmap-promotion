package main

import (
	"encoding/json"
	"io"
	"strconv"
	"strings"
)

type sarifLog struct {
	Version string     `json:"version"`
	Schema  string     `json:"$schema"`
	Runs    []sarifRun `json:"runs"`
}

type sarifRun struct {
	Tool       sarifTool      `json:"tool"`
	Results    []sarifResult  `json:"results"`
	Properties map[string]any `json:"properties"`
}

type sarifTool struct {
	Driver sarifDriver `json:"driver"`
}

type sarifDriver struct {
	Name           string      `json:"name"`
	Version        string      `json:"version"`
	InformationURI string      `json:"informationUri"`
	Rules          []sarifRule `json:"rules"`
}

type sarifRule struct {
	ID               string       `json:"id"`
	ShortDescription sarifMessage `json:"shortDescription"`
	HelpURI          string       `json:"helpUri"`
}

type sarifResult struct {
	RuleID     string          `json:"ruleId"`
	Level      string          `json:"level"`
	Message    sarifMessage    `json:"message"`
	Locations  []sarifLocation `json:"locations"`
	Properties map[string]any  `json:"properties"`
}

type sarifMessage struct {
	Text string `json:"text"`
}

type sarifLocation struct {
	PhysicalLocation sarifPhysicalLocation `json:"physicalLocation"`
}

type sarifPhysicalLocation struct {
	ArtifactLocation sarifArtifactLocation `json:"artifactLocation"`
	Region           sarifRegion           `json:"region"`
}

type sarifArtifactLocation struct {
	URI       string `json:"uri"`
	URIBaseID string `json:"uriBaseId"`
}

type sarifRegion struct {
	StartLine int `json:"startLine"`
}

func writeSARIF(writer io.Writer, output report) error {
	results := make([]sarifResult, 0, len(output.Diagnostics))
	for _, diagnostic := range output.Diagnostics {
		path, line := splitLocation(diagnostic.Location)
		results = append(results, sarifResult{
			RuleID:  diagnostic.RuleID,
			Level:   "warning",
			Message: sarifMessage{Text: diagnostic.Message},
			Locations: []sarifLocation{{PhysicalLocation: sarifPhysicalLocation{
				ArtifactLocation: sarifArtifactLocation{URI: path, URIBaseID: "%SRCROOT%"},
				Region:           sarifRegion{StartLine: line},
			}}},
			Properties: map[string]any{"remediation": diagnostic.Remediation},
		})
	}
	log := sarifLog{
		Version: "2.1.0",
		Schema:  "https://json.schemastore.org/sarif-2.1.0.json",
		Runs: []sarifRun{{
			Tool: sarifTool{Driver: sarifDriver{
				Name: "otelcol-confmap-promotion", Version: output.ToolVersion,
				InformationURI: "https://github.com/kentomk/otelcol-confmap-promotion",
				Rules:          []sarifRule{{ID: "OCP001", ShortDescription: sarifMessage{Text: "Promoted confmap decoder can consume parent sibling keys"}, HelpURI: "https://github.com/kentomk/otelcol-confmap-promotion#rule-ocp001"}},
			}},
			Results: results,
			Properties: map[string]any{
				"unknowns": output.Unknowns,
				"summary":  output.Summary,
				"limits":   output.Limits,
			},
		}},
	}
	encoder := json.NewEncoder(writer)
	encoder.SetEscapeHTML(false)
	return encoder.Encode(log)
}

func splitLocation(value string) (string, int) {
	separator := strings.LastIndex(value, ":")
	if separator < 0 {
		return value, 1
	}
	line, err := strconv.Atoi(value[separator+1:])
	if err != nil || line < 1 {
		return value, 1
	}
	return value[:separator], line
}
