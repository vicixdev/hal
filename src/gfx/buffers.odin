package gfx

import "core:mem"
import hm "core:container/handle_map"

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

	_check_device_selected(location) or_return

	if size < _device_info.limits.min_allocation_size {
		_queue_generic_message(
			.Warning,
			"Small GPU allocation",
			"Small GPU allocation detected (%d bytes). The gfx::alloc procedure should be used to " +
			"allocate big buffers (at least device_info.limits.min_allocation_size bytes, or %d " +
			"bytes for the current device), which should be suballocated by the application using " +
			"custom allocators. The size will be adjusted to %d bytes.",
			size,
			_device_info.limits.min_allocation_size,
			_device_info.limits.min_allocation_size,
			location=location,
		)

		size = _device_info.limits.min_allocation_size
	}

	if !_is_aligned(cast(uintptr)size, _device_info.limits.allocation_alignment) {
		_queue_generic_message(
			.Warning,
			"Unaligned GPU allocation",
			"Unaligned allocation detected (%d bytes). The gfx::alloc procedure should be used to " +
			"allocate large memory aligned buffers (according to device_info.limits.allocation_alignment, " +
			"or %d bytes for the current device). The size will be adjusted to %d bytes.",
			size,
			_device_info.limits.allocation_alignment,
			mem.align_forward_int(size, _device_info.limits.allocation_alignment),
			location=location,
		)

		size = mem.align_forward_int(size, _device_info.limits.allocation_alignment)
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
	if _check_device_selected(location) != nil {
		return
	}

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

gpu_address_of :: proc(buffer: Buffer, location := #caller_location) -> (address: uintptr, res: Result) {
	_check_device_selected(location) or_return

	metadata := _metadata_of(buffer) or_return

	if metadata.memory_type == .Private {
		return buffer.address, nil
	}

	offset := _offset_from_base(buffer, metadata)
	return metadata.gpu_address + offset, nil
}

mark_as_modified :: proc(buffer: Buffer, length: int, location := #caller_location) -> Result {
	_check_device_selected(location) or_return

	metadata := _metadata_of(buffer) or_return

	// NOTE: Only `.Default` can be used to upload data. `.Readback` can only be used for downloading data.
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

prepare_for_readback :: proc(buffer: Buffer, length: int, location := #caller_location) -> Result {
	_check_device_selected(location) or_return

	metadata := _metadata_of(buffer) or_return

	// NOTE: Both `.Default` and `.Readback` can be used for readback (download) purposes.
	if metadata.memory_type == .Private {
		return nil
	}

	when TARGET_API == .Vulkan {
		vk_prepare_for_readback(metadata, buffer, length)
	} else when TARGET_API == .Metal_3 {
		m3_prepare_for_readback(metadata, buffer, length)
	}

	return nil
}

label_buffer :: proc(buffer: Buffer, label: string, location := #caller_location) -> Result {
	_check_device_selected(location) or_return

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

_is_aligned :: proc(p: uintptr, #any_int align: int) -> bool {
	return (p & (uintptr(align) - 1)) == 0
}

_offset_from_base :: proc(buffer: Buffer, metadata: ^_Buffer_Metadata) -> uintptr {
	if (metadata.memory_type == .Private) {
		return buffer.address - metadata.gpu_address
	} else {
		return cast(uintptr)buffer.contents - metadata.cpu_address
	}
}
