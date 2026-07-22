package valuereceiver

import "github.com/kentomk/otelcol-confmap-promotion/testdata/fixtures/confmap"

type Helper struct{}

func (Helper) Unmarshal(*confmap.Conf) error { return nil }

type Config struct {
	Helper
	Encoding string `mapstructure:"encoding"`
}
