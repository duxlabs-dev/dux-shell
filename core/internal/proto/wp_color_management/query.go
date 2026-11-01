package wp_color_management

import (
	"github.com/duxlabs-dev/dux-go/wayland/client"
)

// OutputDescription is the named color encoding of an output's current image
// description. Zero fields mean the corresponding event was not delivered
// (ICC-based or unnamed parametric descriptions).
type OutputDescription struct {
	Primaries    uint32
	TF           uint32
	ReferenceLum uint32
}

// QueryOutputDescription fetches the current image description of an output.
// roundtrip must dispatch pending events on the caller's connection.
func QueryOutputDescription(mgr *WpColorManagerV1, output *client.Output, roundtrip func() error) (OutputDescription, bool) {
	var desc OutputDescription

	cmOutput, err := mgr.GetOutput(output)
	if err != nil {
		return desc, false
	}
	defer cmOutput.Destroy()

	imgDesc, err := cmOutput.GetImageDescription()
	if err != nil {
		return desc, false
	}
	defer imgDesc.Destroy()

	ready := false
	imgDesc.SetReadyHandler(func(WpImageDescriptionV1ReadyEvent) { ready = true })
	imgDesc.SetReady2Handler(func(WpImageDescriptionV1Ready2Event) { ready = true })
	if err := roundtrip(); err != nil || !ready {
		return desc, false
	}

	info, err := imgDesc.GetInformation()
	if err != nil {
		return desc, false
	}

	info.SetPrimariesNamedHandler(func(e WpImageDescriptionInfoV1PrimariesNamedEvent) {
		desc.Primaries = e.Primaries
	})
	info.SetTfNamedHandler(func(e WpImageDescriptionInfoV1TfNamedEvent) {
		desc.TF = e.Tf
	})
	info.SetLuminancesHandler(func(e WpImageDescriptionInfoV1LuminancesEvent) {
		desc.ReferenceLum = e.ReferenceLum
	})
	if err := roundtrip(); err != nil {
		return desc, false
	}

	return desc, true
}
