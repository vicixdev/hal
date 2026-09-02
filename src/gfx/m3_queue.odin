#+build darwin
package vicixdev_gfx

import "core:sync"
import NS "core:sys/darwin/Foundation"
import MTL "vendor:darwin/Metal"
import MTLe "darwext/metal"

m3_Queue_Metadata :: struct {
	queue:	^MTL.CommandQueue,
}

m3_setup_queue :: proc(metadata: ^_Queue_Metadata) -> Result {
	NS.scoped_autoreleasepool()

	queue := m3_device->newCommandQueueWithMaxCommandBufferCount(1)
	if queue == nil {
		return .Generic_Backend_Error
	}

	queue->setLabel(metadata.type == .Default ? NS.AT("Default queue") : NS.AT("Transfer queue"))

	metadata.m3.queue = queue

	return nil
}

m3_destroy_queue :: proc(metadata: ^_Queue_Metadata) {
	NS.scoped_autoreleasepool()

	metadata.m3.queue->release()
}

m3_wait_idle :: proc(metadata: ^_Queue_Metadata) -> Result {
	NS.scoped_autoreleasepool()

	event := m3_device->newSharedEvent()
	defer event->release()

	if sync.guard(&metadata.emission_mutex) {
		command_buffer := metadata.m3.queue->commandBuffer()
		command_buffer->encodeSignalEvent(event, 1)
		command_buffer->commit()
	}

	MTLe.SharedEvent_waitUntilSignaledValue(auto_cast event, 1, max(u64))

	return nil
}
