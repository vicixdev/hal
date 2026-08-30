#+build darwin
package gfx

import NS "core:sys/darwin/Foundation"
import MTL "vendor:darwin/Metal"
import MTLe "darwext/metal"

m3_Semaphore_Metadata :: struct {
	using _: struct #raw_union {
		shared_event:	^MTL.SharedEvent,
		event:		^MTL.Event,
	},
}

m3_create_semaphore :: proc(metadata: ^_Semaphore_Metadata, type: Semaphore_Type) -> Result {
	NS.scoped_autoreleasepool()

	switch type {
	case .Default:
		event := m3_device->newEvent()
		if event == nil {
			return .Out_Of_Gpu_Memory
		}

		metadata.m3.event = event

	case .Cpu_Waitable:
		shared_event := m3_device->newSharedEvent()
		if shared_event == nil {
			return .Out_Of_Gpu_Memory
		}

		metadata.m3.shared_event = shared_event

	}


	return nil
}

m3_destroy_semaphore :: proc(metadata: ^_Semaphore_Metadata) -> Result {
	NS.scoped_autoreleasepool()

	switch metadata.type {
	case .Default:
		metadata.m3.event->release()

	case .Cpu_Waitable:
		metadata.m3.shared_event->release()
	}

	return nil
}

m3_wait_semaphore :: proc(metadata: ^_Semaphore_Metadata, value: int) -> Result {
	NS.scoped_autoreleasepool()

	assert(metadata.type == .Cpu_Waitable)

	MTLe.SharedEvent_waitUntilSignaledValue(auto_cast metadata.m3.shared_event, cast(u64)value, max(u64))

	return nil
}

