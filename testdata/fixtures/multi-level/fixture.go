package multilevel

import "github.com/kentomk/otelcol-confmap-promotion/testdata/fixtures/confmap"

type Helper struct{}

func (*Helper) Unmarshal(*confmap.Conf) error { return nil }

type Middle struct {
	Helper
}

type Config struct {
	Middle
	Encoding string `mapstructure:"encoding"`
}
