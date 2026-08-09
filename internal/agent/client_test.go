package agent

import (
	"bytes"
	"compress/gzip"
	"io"
	"testing"
)

func TestCompressJSONBodyKeepsSmallRequestsAndCompressesLargeOnes(t *testing.T) {
	small := []byte(`{"ok":true}`)
	wire, encoding, err := compressJSONBody(small)
	if err != nil || encoding != "" || !bytes.Equal(wire, small) {
		t.Fatalf("petit corps modifié: encoding=%q err=%v", encoding, err)
	}

	large := bytes.Repeat([]byte(`{"event":"Fabrications terminées"}`), 4096)
	wire, encoding, err = compressJSONBody(large)
	if err != nil || encoding != "gzip" || len(wire) >= len(large)/4 {
		t.Fatalf("compression inefficace: raw=%d wire=%d encoding=%q err=%v", len(large), len(wire), encoding, err)
	}
	reader, err := gzip.NewReader(bytes.NewReader(wire))
	if err != nil {
		t.Fatal(err)
	}
	decoded, err := io.ReadAll(reader)
	if err != nil || !bytes.Equal(decoded, large) {
		t.Fatalf("corps compressé altéré: err=%v", err)
	}
}
