package nocustomunmarshal

type Helper struct{}

type Config struct {
	Helper
	Encoding string `mapstructure:"encoding"`
}
