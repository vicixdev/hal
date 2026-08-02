#+build darwin
package gfx

import "core:fmt"
import NS "core:sys/darwin/Foundation"
import MTL "vendor:darwin/Metal"


@(rodata)
m3_MEMORY_TO_RESOURCEOPTIONS := [Memory]MTL.ResourceOptions {
	.Default	= { .CPUCacheModeWriteCombined, .HazardTrackingModeUntracked },
	.Private	= { .StorageModePrivate, .HazardTrackingModeUntracked },
	.Readback	= { .HazardTrackingModeUntracked },
}


m3_Buffer_Metadata :: struct {
	heap:		^MTL.Heap,
	// This buffer always points to the base of the allocation (offset 0).
	buffer:		^MTL.Buffer,
}

m3_alloc :: proc(metadata: ^_Buffer_Metadata, type: Memory, size: int) -> Result {
	NS.scoped_autoreleasepool()
	
	resource_options := m3_MEMORY_TO_RESOURCEOPTIONS[type]

	heap_desc := MTL.HeapDescriptor.alloc()->init()
	heap_desc->autorelease()

	heap_desc->setResourceOptions(resource_options)
	heap_desc->setSize(cast(NS.UInteger)size)
	heap_desc->setType(.Placement)

	heap := m3_device->newHeap(heap_desc)
	buffer := heap->newBufferWithOptions(cast(NS.UInteger)size, resource_options, 0)

	gpu_address := buffer->gpuAddress()
	cpu_address: rawptr
	if type != .Private {
		cpu_address = buffer->contentsPointer()
	}

	metadata.gpu_address	= cast(uintptr)gpu_address
	metadata.cpu_address	= cast(uintptr)cpu_address
	metadata.m3.heap	= heap
	metadata.m3.buffer	= buffer

	return nil
}


m3_dealloc :: proc(metadata: ^_Buffer_Metadata) {
	metadata.m3.heap->release()
	metadata.m3.buffer->release()
}

// NOTE: If non apple silicon hardware will ever be supported:
//	- Default and readback memory should use MTLStorageModeManaged
//	- m3_mark_as_modified maps to MTLBuffer->didModifyRange()
//	- m3_prepare_for_readback maps to MTLBuffer->synchronizeResource()
m3_mark_as_modified :: proc(metadata: ^_Buffer_Metadata, buffer: Buffer, length: int) {}
m3_prepare_for_readback :: proc(metadata: ^_Buffer_Metadata, buffer: Buffer, length: int) {}

m3_label_buffer :: proc(metadata: ^_Buffer_Metadata, label: string) {

	heap_label := NS.String.alloc()->initWithOdinString(label)
	defer heap_label->release()

	buffer_label := NS.String.alloc()->initWithOdinString(fmt.tprintf("%s (root buffer)", label))
	defer buffer_label->release()

	metadata.m3.heap->setLabel(heap_label)
	metadata.m3.buffer->setLabel(buffer_label)
}

