package nestedsafe

import "github.com/kentomk/otelcol-confmap-promotion/testdata/fixtures/confmap"

type Helper struct {
	QueueSize int `mapstructure:"queue_size"`
}

func (*Helper) Unmarshal(*confmap.Conf) error { return nil }

type Config struct {
	Helper   Helper `mapstructure:"helper"`
	Encoding string `mapstructure:"encoding"`
}
