package screenshot

import (
	"encoding/binary"
	"hash/crc32"

	"github.com/duxlabs-dev/dux-shell/core/internal/proto/wp_color_management"
)

// CICP holds H.273 coding-independent code points describing the color
// encoding of a capture (e.g. BT.2020 primaries + PQ transfer for HDR).
type CICP struct {
	Primaries uint8
	TF        uint8
}

// wp_color_manager_v1 named encoding -> ITU-T H.273 code point
var cicpPrimaries = map[wp_color_management.WpColorManagerV1Primaries]uint8{
	wp_color_management.WpColorManagerV1PrimariesSrgb:        1,
	wp_color_management.WpColorManagerV1PrimariesPalM:        4,
	wp_color_management.WpColorManagerV1PrimariesPal:         5,
	wp_color_management.WpColorManagerV1PrimariesNtsc:        6,
	wp_color_management.WpColorManagerV1PrimariesGenericFilm: 8,
	wp_color_management.WpColorManagerV1PrimariesBt2020:      9,
	wp_color_management.WpColorManagerV1PrimariesCie1931Xyz:  10,
	wp_color_management.WpColorManagerV1PrimariesDciP3:       11,
	wp_color_management.WpColorManagerV1PrimariesDisplayP3:   12,
}

var cicpTF = map[wp_color_management.WpColorManagerV1TransferFunction]uint8{
	wp_color_management.WpColorManagerV1TransferFunctionBt1886:    1,
	wp_color_management.WpColorManagerV1TransferFunctionGamma22:   4,
	wp_color_management.WpColorManagerV1TransferFunctionGamma28:   5,
	wp_color_management.WpColorManagerV1TransferFunctionSt240:     7,
	wp_color_management.WpColorManagerV1TransferFunctionExtLinear: 8,
	wp_color_management.WpColorManagerV1TransferFunctionLog100:    9,
	wp_color_management.WpColorManagerV1TransferFunctionLog316:    10,
	wp_color_management.WpColorManagerV1TransferFunctionXvycc:     11,
	wp_color_management.WpColorManagerV1TransferFunctionSrgb:      13,
	wp_color_management.WpColorManagerV1TransferFunctionExtSrgb:   13,
	wp_color_management.WpColorManagerV1TransferFunctionSt2084Pq:  16,
	wp_color_management.WpColorManagerV1TransferFunctionSt428:     17,
	wp_color_management.WpColorManagerV1TransferFunctionHlg:       18,
}

// cicpFromNamed maps a named output color encoding to CICP. Plain SDR/sRGB
// encodings return nil: untagged PNG already means sRGB, and tagging adds
// only compatibility risk.
func cicpFromNamed(primaries, tf uint32) *CICP {
	p, okP := cicpPrimaries[wp_color_management.WpColorManagerV1Primaries(primaries)]
	t, okT := cicpTF[wp_color_management.WpColorManagerV1TransferFunction(tf)]
	if !okP || !okT {
		return nil
	}

	hdr := false
	switch wp_color_management.WpColorManagerV1TransferFunction(tf) {
	case wp_color_management.WpColorManagerV1TransferFunctionSt2084Pq,
		wp_color_management.WpColorManagerV1TransferFunctionHlg:
		hdr = true
	}

	wide := false
	switch wp_color_management.WpColorManagerV1Primaries(primaries) {
	case wp_color_management.WpColorManagerV1PrimariesBt2020,
		wp_color_management.WpColorManagerV1PrimariesCie1931Xyz,
		wp_color_management.WpColorManagerV1PrimariesDciP3,
		wp_color_management.WpColorManagerV1PrimariesDisplayP3:
		wide = true
	}

	if !hdr && !wide {
		return nil
	}
	return &CICP{Primaries: p, TF: t}
}

func (c *CICP) chunks() [][]byte {
	if c == nil {
		return nil
	}
	return [][]byte{c.chunk()}
}

func (c *CICP) chunk() []byte {
	payload := []byte{'c', 'I', 'C', 'P', c.Primaries, c.TF, 0, 1} // matrix=RGB, full range
	chunk := binary.BigEndian.AppendUint32(make([]byte, 0, 16), 4)
	chunk = append(chunk, payload...)
	return binary.BigEndian.AppendUint32(chunk, crc32.ChecksumIEEE(payload))
}

// outputCICP queries the output's image description via wp_color_management_v1.
// Returns nil unless the output uses a wide-gamut or HDR encoding.
func (s *Screenshoter) outputCICP(output *WaylandOutput) *CICP {
	if s.colorMgr == nil {
		return nil
	}

	desc, ok := wp_color_management.QueryOutputDescription(s.colorMgr, output.wlOutput, s.roundtrip)
	if !ok {
		return nil
	}
	return cicpFromNamed(desc.Primaries, desc.TF)
}
