#+build darwin
package gfx

import "core:fmt"
import "core:slice"
import NS "core:sys/darwin/Foundation"
import MTL "vendor:darwin/Metal"

m3_Buffer_Metadata :: struct {
	heap:		^MTL.Heap,
	// This buffer always points to the base of the allocation (offset 0).
	buffer:		^MTL.Buffer,

	index_in_residency_set:	int,
}

m3_residency_set:		[dynamic]^MTL.Heap
m3_residency_set_handles:	[dynamic]Handle

m3_alloc :: proc(metadata: ^_Buffer_Metadata, type: Memory, size: int) -> Result {
	NS.scoped_autoreleasepool()
	
	resource_options := m3_MEMORY_TO_RESOURCEOPTIONS[type]

	heap_desc := MTL.HeapDescriptor.alloc()->init()
	heap_desc->autorelease()

	heap_desc->setResourceOptions(resource_options)
	heap_desc->setSize(cast(NS.UInteger)size)
	heap_desc->setType(.Placement)

	heap := m3_device->newHeap(heap_desc)
	if heap == nil {
		return .Out_Of_Gpu_Memory
	}

	buffer := heap->newBufferWithOptions(cast(NS.UInteger)size, resource_options, 0)
	assert(buffer != nil, "If the MTLHeap allocation succeded, then the buffer allocation should succede.")

	gpu_address := buffer->gpuAddress()
	cpu_address: rawptr
	if type != .Private {
		cpu_address = buffer->contentsPointer()
	}

	metadata.gpu_address	= cast(uintptr)gpu_address
	metadata.cpu_address	= cast(uintptr)cpu_address
	metadata.m3.heap	= heap
	metadata.m3.buffer	= buffer

	metadata.m3.index_in_residency_set = len(m3_residency_set)
	append(&m3_residency_set, heap)
	append(&m3_residency_set_handles, metadata.handle)

	return nil
}

m3_dealloc :: proc(metadata: ^_Buffer_Metadata) {
	metadata.m3.heap->release()
	metadata.m3.buffer->release()

	last_buffer_metadata, last_buffer_res := _metadata_of(Buffer { handle = slice.last(m3_residency_set_handles[:]) })
	assert(last_buffer_res == nil)

	last_buffer_metadata.m3.index_in_residency_set = metadata.m3.index_in_residency_set

	unordered_remove(&m3_residency_set, metadata.m3.index_in_residency_set)
	unordered_remove(&m3_residency_set_handles, metadata.m3.index_in_residency_set)
}

m3_label_buffer :: proc(metadata: ^_Buffer_Metadata, label: string) -> Result {

	heap_label := NS.String.alloc()->initWithOdinString(label)
	defer heap_label->release()

	buffer_label := NS.String.alloc()->initWithOdinString(fmt.tprintf("%s (root buffer)", label))
	defer buffer_label->release()

	metadata.m3.heap->setLabel(heap_label)
	metadata.m3.buffer->setLabel(buffer_label)

	return nil
}

@(rodata)
m3_MEMORY_TO_RESOURCEOPTIONS := [Memory]MTL.ResourceOptions {
	.Default	= { .CPUCacheModeWriteCombined, .HazardTrackingModeUntracked },
	.Staging	= { .CPUCacheModeWriteCombined, .HazardTrackingModeUntracked },
	.Private	= { .StorageModePrivate, .HazardTrackingModeUntracked },
	.Readback	= { .HazardTrackingModeUntracked },
}

