package release

import "testing"

func TestTranslateReplacementBackrefsWrapsCaptureNumbers(t *testing.T) {
	t.Parallel()

	got := translateReplacementBackrefs(`\1git+https://example.test/ref\2`)
	want := `${1}git+https://example.test/ref${2}`
	if got != want {
		t.Fatalf("translateReplacementBackrefs() = %q, want %q", got, want)
	}
}
