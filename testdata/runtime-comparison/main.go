package main

import (
	"encoding/json"
	"fmt"
	"os"
	"strings"

	"go.opentelemetry.io/collector/confmap"
)

type helper struct {
	QueueSize int `mapstructure:"queue_size"`
}

func (cfg *helper) Unmarshal(input *confmap.Conf) error {
	return input.Unmarshal(cfg)
}

type ignoreHelper struct {
	QueueSize int `mapstructure:"queue_size"`
}

func (cfg *ignoreHelper) Unmarshal(input *confmap.Conf) error {
	return input.Unmarshal(cfg, confmap.WithIgnoreUnused())
}

type unsafeConfig struct {
	helper   `mapstructure:",squash"`
	Encoding string `mapstructure:"encoding"`
}

type ignoredConfig struct {
	ignoreHelper `mapstructure:",squash"`
	Encoding     string `mapstructure:"encoding"`
}

type nestedConfig struct {
	Helper   helper `mapstructure:"helper"`
	Encoding string `mapstructure:"encoding"`
}

type result struct {
	Mode      string `json:"mode"`
	Outcome   string `json:"outcome"`
	Encoding  string `json:"encoding"`
	QueueSize int    `json:"queueSize"`
}

func main() {
	if len(os.Args) != 2 {
		fail("mode must be unsafe, nested, or ignore")
	}
	var output result
	switch os.Args[1] {
	case "unsafe":
		cfg := unsafeConfig{}
		err := confmap.NewFromStringMap(map[string]any{"queue_size": 17, "encoding": "otlp"}).Unmarshal(&cfg)
		if err == nil || !strings.Contains(err.Error(), "encoding") || !strings.Contains(err.Error(), "invalid") {
			fail("unsafe mode did not reject the sibling key")
		}
		output = result{Mode: "unsafe", Outcome: "rejected-sibling", Encoding: cfg.Encoding, QueueSize: cfg.QueueSize}
	case "nested":
		cfg := nestedConfig{}
		err := confmap.NewFromStringMap(map[string]any{"helper": map[string]any{"queue_size": 17}, "encoding": "otlp"}).Unmarshal(&cfg)
		if err != nil || cfg.Encoding != "otlp" || cfg.Helper.QueueSize != 17 {
			fail("nested mode did not preserve both fields")
		}
		output = result{Mode: "nested", Outcome: "preserved", Encoding: cfg.Encoding, QueueSize: cfg.Helper.QueueSize}
	case "ignore":
		cfg := ignoredConfig{}
		err := confmap.NewFromStringMap(map[string]any{"queue_size": 17, "encoding": "otlp"}).Unmarshal(&cfg)
		if err != nil || cfg.Encoding != "" || cfg.QueueSize != 17 {
			fail("ignore mode did not reproduce silent sibling loss")
		}
		output = result{Mode: "ignore", Outcome: "silent-sibling-loss", Encoding: cfg.Encoding, QueueSize: cfg.QueueSize}
	default:
		fail("mode must be unsafe, nested, or ignore")
	}
	if err := json.NewEncoder(os.Stdout).Encode(output); err != nil {
		fail("could not encode result")
	}
}

func fail(message string) {
	_, _ = fmt.Fprintln(os.Stderr, "runtime comparison failed:", message)
	os.Exit(1)
}
