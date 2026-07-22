//go:build windows

package buildtagfixture

import "github.com/kentomk/otelcol-confmap-promotion/testdata/fixtures/confmap"

type Helper struct{}

func (*Helper) Unmarshal(*confmap.Conf) error { return nil }

type WindowsConfig struct {
	Helper
	Encoding string `mapstructure:"encoding"`
}
