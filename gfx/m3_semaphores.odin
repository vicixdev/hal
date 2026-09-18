#+build darwin
package vicixdev_gfx

/*
This Source Code Form is subject to the terms of the Mozilla Public
License, v. 2.0. If a copy of the MPL was not distributed with this
file, You can obtain one at https://mozilla.org/MPL/2.0/.
*/

import NS "core:sys/darwin/Foundation"
import MTL "vendor:darwin/Metal"
import MTLe "darwext/metal"

_m3_Semaphore_Metadata :: struct {
	// Only when `.Default` semaphore.
	value:	u64,

	using _: struct #raw_union {
		shared_event:	^MTL.SharedEvent,
		event:		^MTL.Event,
	},
}

_m3_create_semaphore :: proc(metadata: ^_Semaphore_Metadata, type: Semaphore_Type) -> Result {
	NS.scoped_autoreleasepool()

	switch type {
	// NOTE: In Metal 4, MTLFences can be used across queues, so, when the time comes for a Metal 4 backend, a
	//	MTLFence should be used for `.Default` semaphores.
	case .Default, .Timeline:
		event := _m3_device->newEvent()
		if event == nil {
			return .Out_Of_Gpu_Memory
		}

		metadata.m3.event = event

	case .Cpu:
		shared_event := _m3_device->newSharedEvent()
		if shared_event == nil {
			return .Out_Of_Gpu_Memory
		}

		metadata.m3.shared_event = shared_event

	case .Surface:
		unreachable()
	}


	return nil
}

_m3_destroy_semaphore :: proc(metadata: ^_Semaphore_Metadata) -> Result {
	NS.scoped_autoreleasepool()

	switch metadata.type {
	case .Default, .Timeline:
		metadata.m3.event->release()

	case .Cpu:
		metadata.m3.shared_event->release()

	case .Surface:
	}

	return nil
}

_m3_wait_semaphore :: proc(metadata: ^_Semaphore_Metadata, value: int) -> Result {
	NS.scoped_autoreleasepool()

	assert(metadata.type == .Cpu)

	MTLe.SharedEvent_waitUntilSignaledValue(auto_cast metadata.m3.shared_event, cast(u64)value, max(u64))

	return nil
}

_m3_emit_signal_semaphore :: proc(command_buffer: ^MTL.CommandBuffer, metadata: ^_Semaphore_Metadata, value: int) {
	switch metadata.type {
	case .Default:
		assert(value == 0)

		/*
		NOTE: This is fine since the command is called at emission time, so:
			- cb1: wait for s1
			- cb2: signal for s1
			- submit(cb1, cb2) -> cb1 does not wait, since it not in the Signaled state, as expected.

			- cb1: signal for s1
			- cb2: wait for s1
			- submit(cb1, cb2) -> cb1 does signal, cb2 does wait, as expected.
		*/
		metadata.m3.value += 1
		command_buffer->encodeSignalEvent(metadata.m3.event, metadata.m3.value)

	case .Timeline, .Cpu:
		command_buffer->encodeSignalEvent(metadata.m3.event, cast(u64)value)

	case .Surface:
		// Noop on Metal 3
	}
}

_m3_emit_wait_semaphore :: proc(command_buffer: ^MTL.CommandBuffer, metadata: ^_Semaphore_Metadata, value: int) {
	switch metadata.type {
	case .Default:
		assert(value == 0)

		command_buffer->encodeWaitForEvent(metadata.m3.event, metadata.m3.value)

	case .Timeline, .Cpu:
		command_buffer->encodeWaitForEvent(metadata.m3.event, cast(u64)value)

	case .Surface:
		// Noop on Metal 3
	}
}

