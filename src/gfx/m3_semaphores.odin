#+build darwin
package gfx

import MTL "vendor:darwin/Metal"
import MTLe "shared:darwext/metal"

m3_Semaphore_Metadata :: struct {
	event:	^MTL.SharedEvent,
}

m3_create_semaphore :: proc(metadata: ^_Semaphore_Metadata) -> Result {
	shared_event := m3_device->newSharedEvent()
	if shared_event == nil {
		return .Out_Of_Gpu_Memory
	}

	metadata.m3.event = shared_event

	return nil
}

m3_destroy_semaphore :: proc(metadata: ^_Semaphore_Metadata) -> Result {
	metadata.m3.event->release()

	return nil
}

m3_wait_semaphore :: proc(metadata: ^_Semaphore_Metadata, value: int) -> Result {

	MTLe.SharedEvent_waitUntilSignaledValue(auto_cast metadata.m3.event, cast(u64)value, max(u64))

	return nil
}

