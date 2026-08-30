#+build darwin
package gfx

import NS "core:sys/darwin/Foundation"
import MTL "vendor:darwin/Metal"

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
