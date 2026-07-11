#+build darwin
package gfx

import "core:fmt"
import hm "core:container/handle_map"
import NS "core:sys/darwin/Foundation"
import MTL "vendor:darwin/Metal"


@(rodata)
_MEMORY_TO_RESOURCEOPTIONS := [Memory]MTL.ResourceOptions {
	.Default	= { .CPUCacheModeWriteCombined, .HazardTrackingModeUntracked },
	.Private	= { .StorageModePrivate, .HazardTrackingModeUntracked },
	.Readback	= { .HazardTrackingModeUntracked },
}

// @(rodata)
// _MEMORY_TO_RESOURCEOPTIONS := [Memory]MTL.ResourceOptions {
// 	.Default	= { .CPUCacheModeWriteCombined },
// 	.Private	= { .StorageModePrivate },
// 	.Readback	= {},
// }


_Buffer_Metadata :: struct {
	handle:		Handle,

	memory:		Memory,

	heap:		^MTL.Heap,
	// This buffer always points to the base of the allocation (offset 0).
	buffer:		^MTL.Buffer,
}

_buffers:	hm.Dynamic_Handle_Map(_Buffer_Metadata, Handle)

_alloc :: proc(type: Memory, size: int) -> (ret: Buffer, res: Result) {
	NS.scoped_autoreleasepool()
	
	resource_options := _MEMORY_TO_RESOURCEOPTIONS[type]

	heap_desc := MTL.HeapDescriptor.alloc()->init()
	heap_desc->autorelease()

	heap_desc->setResourceOptions(resource_options)
	heap_desc->setSize(cast(NS.UInteger)size)
	heap_desc->setType(.Placement)

	heap := _device->newHeap(heap_desc)
	buffer := heap->newBufferWithOptions(cast(NS.UInteger)size, resource_options, 0)

	metadata := _Buffer_Metadata {
		memory	= type,
		heap	= heap,
		buffer	= buffer,
	}

	handle := hm.dynamic_add(&_buffers, metadata) or_return

	ret.handle = handle
	if (type == .Default || type == .Readback) {
		ret.contents = buffer->contentsPointer()
	} else {
		ret.reference = cast(GpuDataRef)buffer->gpuAddress()
	}

	return
}


_dealloc :: proc(buffer: Buffer) {
	metadata, ok := hm.get(&_buffers, buffer.handle)
	if !ok {
		return
	}
	
	metadata.heap->release()
	metadata.buffer->release()

	hm.remove(&_buffers, buffer.handle)
}

_gpu_reference_of :: proc(buffer: Buffer) -> (GpuDataRef, Result) {
	metadata, ok := hm.get(&_buffers, buffer.handle)
	if !ok {
		return 0, .Invalid_Buffer
	}

	if (metadata.memory == .Private) {
		return buffer.reference, nil
	}


	offset := _offset_from_base(buffer, metadata)
	return cast(uintptr)metadata.buffer->gpuAddress() + offset, nil
	
}

_mark_as_modified :: proc(buffer: Buffer, length: int) {}

_label_buffer :: proc(buffer: Buffer, label: string) {
	metadata, ok := hm.get(&_buffers, buffer.handle)
	if !ok {
		return
	}

	heap_label := NS.String.alloc()->initWithOdinString(label)
	defer heap_label->release()

	buffer_label := NS.String.alloc()->initWithOdinString(fmt.tprintf("%s (root buffer)", label))
	defer buffer_label->release()

	metadata.heap->setLabel(heap_label)
	metadata.buffer->setLabel(buffer_label)
}

_offset_from_base :: proc(buffer: Buffer, metadata: ^_Buffer_Metadata) -> uintptr {
	if (metadata.memory == .Private) {
		return buffer.reference - cast(uintptr)metadata.buffer->gpuAddress()
	} else {
		return cast(uintptr)buffer.contents - cast(uintptr)metadata.buffer->contentsPointer()
	}
}

