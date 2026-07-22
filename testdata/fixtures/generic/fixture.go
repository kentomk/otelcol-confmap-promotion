package genericfixture

import "github.com/kentomk/otelcol-confmap-promotion/testdata/fixtures/confmap"

type Helper[T any] struct{}

func (*Helper[T]) Unmarshal(*confmap.Conf) error { return nil }

type Config struct {
	Helper[int]
	Encoding string `mapstructure:"encoding"`
}
