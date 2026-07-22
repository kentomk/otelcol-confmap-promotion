package wrongsignature

type Helper struct{}

func (*Helper) Unmarshal([]byte) error { return nil }

type Config struct {
	Helper
	Encoding string `mapstructure:"encoding"`
}
