#+build darwin
package vicixdev_gfx

/*
This Source Code Form is subject to the terms of the Mozilla Public
License, v. 2.0. If a copy of the MPL was not distributed with this
file, You can obtain one at https://mozilla.org/MPL/2.0/.
*/

import "core:sync"
import NS "core:sys/darwin/Foundation"
import MTL "vendor:darwin/Metal"
import MTLe "darwext/metal"

_m3_Queue_Metadata :: struct {
	queue:	^MTL.CommandQueue,
}

_m3_setup_queue :: proc(metadata: ^_Queue_Metadata) -> Result {
	NS.scoped_autoreleasepool()

	queue := _m3_device->newCommandQueueWithMaxCommandBufferCount(1)
	if queue == nil {
		return .Generic_Backend_Error
	}

	queue->setLabel(metadata.type == .Default ? NS.AT("Default queue") : NS.AT("Transfer queue"))

	metadata.m3.queue = queue

	return nil
}

_m3_destroy_queue :: proc(metadata: ^_Queue_Metadata) {
	NS.scoped_autoreleasepool()

	metadata.m3.queue->release()
}

_m3_wait_idle :: proc(metadata: ^_Queue_Metadata) -> Result {
	NS.scoped_autoreleasepool()

	event := _m3_device->newSharedEvent()
	defer event->release()

	if sync.guard(&metadata.emission_mutex) {
		command_buffer := metadata.m3.queue->commandBuffer()
		command_buffer->encodeSignalEvent(event, 1)
		command_buffer->commit()
	}

	MTLe.SharedEvent_waitUntilSignaledValue(auto_cast event, 1, max(u64))

	return nil
}
