#+build darwin
package gfx

import MTL "vendor:darwin/Metal"

m3_Fence_Metadata :: struct {
	event:	^MTL.Event,
}

m3_create_fence :: proc(metadata: ^_Fence_Metadata) -> Result {
	event := m3_device->newEvent()
	if event == nil {
		return .Out_Of_Gpu_Memory
	}

	metadata.m3.event = event

	return nil
}

m3_destroy_fence :: proc(metadata: ^_Fence_Metadata) {
	metadata.m3.event->release()
}


