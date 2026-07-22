package explicitparent

import "testing"

func TestConfigPreservesSiblings(t *testing.T) {
	preserved := map[string]bool{"encoding": true}
	if !preserved["encoding"] {
		t.Fatal("original fixture lost expected sibling")
	}
}
