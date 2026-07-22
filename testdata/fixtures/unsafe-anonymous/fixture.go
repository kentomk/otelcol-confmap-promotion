package unsafeanonymous

import "github.com/kentomk/otelcol-confmap-promotion/testdata/fixtures/confmap"

type Helper struct {
	QueueSize int `mapstructure:"queue_size"`
}

func (*Helper) Unmarshal(*confmap.Conf) error { return nil }

type Config struct {
	Helper
	Encoding string `mapstructure:"encoding"`
}
