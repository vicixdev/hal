#+build darwin
package gfx

import MTL "vendor:darwin/Metal"

m3_Fence_Metadata :: struct {
	fence:	^MTL.Fence,
}

m3_create_fence :: proc(metadata: ^_Fence_Metadata) -> Result {
	fence := m3_device->newFence()
	if fence == nil {
		return .Out_Of_Gpu_Memory
	}

	metadata.m3.fence = fence

	return nil
}

m3_destroy_fence :: proc(metadata: ^_Fence_Metadata) {
	metadata.m3.fence->release()
}


