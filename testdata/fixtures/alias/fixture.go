package aliasfixture

import "github.com/kentomk/otelcol-confmap-promotion/testdata/fixtures/confmap"

type Helper struct{}

func (*Helper) Unmarshal(*confmap.Conf) error { return nil }

type HelperAlias = Helper

type Config struct {
	HelperAlias
	Encoding string `mapstructure:"encoding"`
}
