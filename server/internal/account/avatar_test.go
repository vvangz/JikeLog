package account

import (
	"bytes"
	"encoding/binary"
	"errors"
	"image"
	"image/color"
	"image/jpeg"
	"image/png"
	"net/http"
	"testing"

	"github.com/vvangz/JikeLog/server/internal/platform/httpx"
)

func makeTestPNG(t *testing.T, w, h int) []byte {
	t.Helper()
	img := image.NewRGBA(image.Rect(0, 0, w, h))
	img.Set(0, 0, color.RGBA{R: 0x33, G: 0x4A, B: 0xC0, A: 0xFF})
	var buf bytes.Buffer
	if err := png.Encode(&buf, img); err != nil {
		t.Fatal(err)
	}
	return buf.Bytes()
}

func makeTestJPEG(t *testing.T, w, h int) []byte {
	t.Helper()
	img := image.NewRGBA(image.Rect(0, 0, w, h))
	img.Set(0, 0, color.RGBA{R: 0x33, G: 0x4A, B: 0xC0, A: 0xFF})
	var buf bytes.Buffer
	if err := jpeg.Encode(&buf, img, &jpeg.Options{Quality: 85}); err != nil {
		t.Fatal(err)
	}
	return buf.Bytes()
}

func makeTestWebPVP8(w, h uint16) []byte {
	b := make([]byte, 30)
	copy(b[0:4], "RIFF")
	binary.LittleEndian.PutUint32(b[4:8], 22)
	copy(b[8:12], "WEBP")
	copy(b[12:16], "VP8 ")
	binary.LittleEndian.PutUint32(b[16:20], 10)
	b[23], b[24], b[25] = 0x9d, 0x01, 0x2a
	binary.LittleEndian.PutUint16(b[26:28], w)
	binary.LittleEndian.PutUint16(b[28:30], h)
	return b
}

func makeTestWebPVP8L(w, h uint32) []byte {
	b := make([]byte, 25)
	copy(b[0:4], "RIFF")
	binary.LittleEndian.PutUint32(b[4:8], 17)
	copy(b[8:12], "WEBP")
	copy(b[12:16], "VP8L")
	binary.LittleEndian.PutUint32(b[16:20], 5)
	b[20] = 0x2f
	bits := (w - 1) | ((h - 1) << 14)
	binary.LittleEndian.PutUint32(b[21:25], bits)
	return b
}

func makeTestWebPVP8X(w, h uint32) []byte {
	b := make([]byte, 30)
	copy(b[0:4], "RIFF")
	binary.LittleEndian.PutUint32(b[4:8], 22)
	copy(b[8:12], "WEBP")
	copy(b[12:16], "VP8X")
	binary.LittleEndian.PutUint32(b[16:20], 10)
	wm := w - 1
	hm := h - 1
	b[24], b[25], b[26] = byte(wm), byte(wm>>8), byte(wm>>16)
	b[27], b[28], b[29] = byte(hm), byte(hm>>8), byte(hm>>16)
	return b
}

func TestValidateAvatarImage(t *testing.T) {
	pngBytes := makeTestPNG(t, 64, 64)
	jpgBytes := makeTestJPEG(t, 64, 64)

	cases := []struct {
		name     string
		declared string
		raw      []byte
		wantMIME string
		wantExt  string
		wantErr  bool
	}{
		{"valid png", "image/png", pngBytes, "image/png", ".png", false},
		{"valid jpeg", "image/jpeg", jpgBytes, "image/jpeg", ".jpg", false},
		{"valid webp vp8", "image/webp", makeTestWebPVP8(128, 128), "image/webp", ".webp", false},
		{"valid webp vp8l", "image/webp", makeTestWebPVP8L(256, 256), "image/webp", ".webp", false},
		{"valid webp vp8x", "image/webp", makeTestWebPVP8X(512, 512), "image/webp", ".webp", false},
		{"empty", "image/png", nil, "", "", true},
		{"too large", "image/png", make([]byte, MaxAvatarBytes+1), "", "", true},
		{"svg disguised as png", "image/png", []byte("<svg xmlns='http://www.w3.org/2000/svg'/>"), "", "", true},
		{"mime mismatch png as jpeg", "image/jpeg", pngBytes, "", "", true},
		{"corrupt png", "image/png", []byte{0x89, 'P', 'N', 'G', '\r', '\n', 0x1a, '\n', 0, 0}, "", "", true},
		{"corrupt jpeg", "image/jpeg", []byte{0xff, 0xd8, 0xff, 0x00, 0x01}, "", "", true},
		{"corrupt webp", "image/webp", []byte("RIFF\x10\x00\x00\x00WEBPVP8 \x00\x00\x00\x00bad"), "", "", true},
		{"dimension exceeded webp", "image/webp", makeTestWebPVP8X(5000, 128), "", "", true},
	}

	for _, tc := range cases {
		t.Run(tc.name, func(t *testing.T) {
			mime, ext, err := validateAvatarImage(tc.declared, tc.raw)
			if tc.wantErr {
				if err == nil {
					t.Fatalf("期望校验失败，实际成功: mime=%q ext=%q", mime, ext)
				}
				var apiErr *httpx.Error
				if !errors.As(err, &apiErr) || apiErr.Status != http.StatusUnprocessableEntity {
					t.Fatalf("期望 422 校验错误，got %v", err)
				}
				return
			}
			if err != nil {
				t.Fatalf("期望成功，got err=%v", err)
			}
			if mime != tc.wantMIME || ext != tc.wantExt {
				t.Fatalf("got (%q, %q), want (%q, %q)", mime, ext, tc.wantMIME, tc.wantExt)
			}
		})
	}
}
