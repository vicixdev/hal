package gfx

import "core:mem"
import hm "core:container/handle_map"

ALLOCATION_MIN_ALIGN :: 16 * mem.Kilobyte

Memory :: enum {
	Default,
	Private,
	Readback,
}

Buffer :: struct {
	handle:  Handle,
	using _: struct #raw_union {
		// If the memory type is `Default` or `Readback` it contains the Cpu Mapped Virtual Address.
		contents:	rawptr,
		// If the memory type is `Private` contains the Gpu Virtual Address of the buffer.
		address:	uintptr,
	},
}

_Buffer_Metadata :: struct {
	handle:		Handle,

	memory_type:	Memory,
	size:		int,

	cpu_address:	uintptr,
	gpu_address:	uintptr,

	using platform: struct #raw_union {
		m3:	m3_Buffer_Metadata,
		vk:	vk_Buffer_Metadata,
	},
}

_buffers: hm.Dynamic_Handle_Map(_Buffer_Metadata, Handle)

alloc :: proc(type: Memory, size: int, location := #caller_location) -> (buffer: Buffer, res: Result) {
	size := size

	if size < ALLOCATION_MIN_ALIGN {
		_queue_generic_message(
			.Warning,
			"Small GPU allocation",
			"Small GPU allocation detected (%d bytes). The gfx::alloc procedure should be used to " +
			"allocate big buffers (>= 16 kilobytes), which should be suballocated by the application " +
			"using custom allocators. The size will be adjusted to 16 kilobytes.",
			size,
			location=location,
		)

		size = ALLOCATION_MIN_ALIGN
	}

	if !_is_aligned(cast(uintptr)size, ALLOCATION_MIN_ALIGN) {
		_queue_generic_message(
			.Warning,
			"Unaligned GPU allocation",
			"Unaligned allocation detected (%d bytes). The gfx::alloc procedure should be used to " +
			"allocate big memory aligned buffers (with 16 kilobytes alignements). The size will be " +
			"up-aligned.",
			size,
			location=location,
		)

		size = mem.align_forward_int(size, ALLOCATION_MIN_ALIGN)
	}

	handle, metadata := _add_buffer_metadata() or_return
	defer if res != nil do _remove_buffer_metadata(handle)

	metadata.size		= size
	metadata.memory_type	= type

	when TARGET_API == .Vulkan {
		vk_alloc(metadata, type, size) or_return
	} else when TARGET_API == .Metal_3 {
		m3_alloc(metadata, type, size) or_return
	}

	buffer.handle = handle
	if type == .Private {
		buffer.address = metadata.gpu_address
	} else {
		buffer.contents = cast(rawptr)metadata.cpu_address
	}

	return
}

dealloc :: proc(buffer: Buffer, location := #caller_location) {
	metadata, res := _metadata_of(buffer)
	if res != nil {
		return
	}

	when TARGET_API == .Vulkan {
		vk_dealloc(metadata)
	} else when TARGET_API == .Metal_3 {
		m3_dealloc(metadata)
	}

	hm.remove(&_buffers, buffer.handle)
}

gpu_address_of :: proc(buffer: Buffer) -> (address: uintptr, res: Result) {
	metadata := _metadata_of(buffer) or_return

	if metadata.memory_type == .Private {
		return buffer.address, nil
	}

	offset := _offset_from_base(buffer, metadata)
	return metadata.gpu_address + offset, nil
}

mark_as_modified :: proc(buffer: Buffer, length: int) -> Result {
	metadata := _metadata_of(buffer) or_return

	if metadata.memory_type != .Default {
		return nil
	}

	when TARGET_API == .Vulkan {
		vk_mark_as_modified(metadata, buffer, length)
	} else when TARGET_API == .Metal_3 {
		m3_mark_as_modified(metadata, buffer, length)
	}

	return nil
}

prepare_for_readback :: proc(buffer: Buffer, length: int) -> Result {
	metadata := _metadata_of(buffer) or_return

	if metadata.memory_type != .Readback {
		return nil
	}

	when TARGET_API == .Vulkan {
		vk_prepare_for_readback(metadata, buffer, length)
	} else when TARGET_API == .Metal_3 {
		m3_prepare_for_readback(metadata, buffer, length)
	}

	return nil
}

label_buffer :: proc(buffer: Buffer, label: string) -> Result {
	metadata := _metadata_of(buffer) or_return

	when TARGET_API == .Vulkan {
		vk_label_buffer(metadata, label)
	} else when TARGET_API == .Metal_3 {
		m3_label_buffer(metadata, label)
	}

	return nil
}

_buffer_metadata_of :: proc(buffer: Buffer) -> (^_Buffer_Metadata, Result) {
	metadata, ok := hm.get(&_buffers, buffer.handle)
	if !ok {
		return nil, .Invalid_Buffer
	}
	
	return metadata, nil
}

_add_buffer_metadata :: proc() -> (handle: Handle, metadata: ^_Buffer_Metadata, res: Result) {
	handle = hm.add(&_buffers, _Buffer_Metadata {}) or_return
	metadata_ok: bool
	metadata, metadata_ok = hm.get(&_buffers, handle)
	assert(metadata_ok)

	return
}

_remove_buffer_metadata :: proc(handle: Handle) {
	hm.remove(&_buffers, handle)
}

_is_aligned :: proc(p: uintptr, align: int) -> bool {
	return (p & (uintptr(align) - 1)) == 0
}

_offset_from_base :: proc(buffer: Buffer, metadata: ^_Buffer_Metadata) -> uintptr {
	if (metadata.memory_type == .Private) {
		return buffer.address - metadata.gpu_address
	} else {
		return cast(uintptr)buffer.contents - metadata.cpu_address
	}
}
