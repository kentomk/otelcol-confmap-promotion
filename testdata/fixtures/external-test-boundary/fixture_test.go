package externaltestboundary_test

import "github.com/kentomk/otelcol-confmap-promotion/testdata/fixtures/confmap"

type helper struct{}

func (*helper) Unmarshal(*confmap.Conf) error { return nil }

type fixtureOnlyConfig struct {
	helper
	Encoding string `mapstructure:"encoding"`
}
