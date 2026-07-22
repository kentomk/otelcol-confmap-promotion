package unsafesquash

import "github.com/kentomk/otelcol-confmap-promotion/testdata/fixtures/confmap"

type Helper struct{}

func (*Helper) Unmarshal(*confmap.Conf) error { return nil }

type Config struct {
	Queue            Helper `mapstructure:",squash"`
	CompressInMemory bool   `mapstructure:"compress_in_memory"`
	PayloadCodec     string `mapstructure:"payload_codec"`
}
