package gfx

import "base:runtime"
import "core:mem"
import "core:sync"
import hm "core:container/handle_map"

Memory :: enum {
	Default,
	Private,
	Readback,
	Staging,
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

_buffers:	hm.Dynamic_Handle_Map(_Buffer_Metadata, Handle)
_buffers_mutex:	sync.RW_Mutex

alloc :: proc(type: Memory, size: int, location := #caller_location) -> (buffer: Buffer, res: Result) {
	size := size

	_check_device_selected(location) or_return

	if size < _device_info.limits.min_allocation_size {
		_log_generic_message(
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
		_log_generic_message(
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
		res = vk_alloc(metadata, type, size)
	} else when TARGET_API == .Metal_3 {
		res = m3_alloc(metadata, type, size)
	}

	_check_specific_result(
		res,
		.Out_Of_Gpu_Memory,
		.Warning,
		"Out of GPU memory",
		"The requested allocation of %d bytes failed: not enough free GPU memory.",
		size,
		location=location,
	) or_return
	_check_generic_backend_error(res, location) or_return

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

	metadata, metadata_res := _metadata_of(buffer)
	_check_buffer_handle(metadata_res, buffer, location)
	if metadata_res != nil {
		return
	}

	when TARGET_API == .Vulkan {
		vk_dealloc(metadata)
	} else when TARGET_API == .Metal_3 {
		m3_dealloc(metadata)
	}

	_remove_buffer_metadata(buffer.handle)
}

gpu_address_of :: proc(buffer: Buffer, location := #caller_location) -> (address: uintptr, res: Result) {
	_check_device_selected(location) or_return

	metadata, metadata_res := _metadata_of(buffer)
	_check_buffer_handle(metadata_res, buffer, location) or_return

	if metadata.memory_type == .Private {
		return buffer.address, nil
	}

	offset := _offset_from_base(buffer, metadata)
	return metadata.gpu_address + offset, nil
}

label_buffer :: proc(buffer: Buffer, label: string, location := #caller_location) {
	if _check_device_selected(location) != nil do return

	metadata, metadata_res := _metadata_of(buffer)
	_check_buffer_handle(metadata_res, buffer, location)
	if metadata_res != nil {
		return
	}

	res: Result
	when TARGET_API == .Vulkan {
		res = vk_label_buffer(metadata, label)
	} else when TARGET_API == .Metal_3 {
		res = m3_label_buffer(metadata, label)
	}

	_check_generic_backend_error(res, location)
}

_check_buffer_handle :: proc(result: Result, buffer: Buffer, location: runtime.Source_Code_Location) -> Result {
	_check_result(
		result,
		.Warning,
		"Invalid resource handle",
		"Invalid buffer handle (%v).",
		buffer.handle,
		location=location,
	) or_return
	return nil
}

_buffer_metadata_of :: proc(buffer: Buffer) -> (metadata: ^_Buffer_Metadata, res: Result) {
	sync.shared_guard(&_buffers_mutex)

	metadata_ok: bool
	metadata, metadata_ok = hm.get(&_buffers, buffer.handle)
	if !metadata_ok {
		return nil, .Invalid_Buffer
	}
	
	return metadata, nil
}

_add_buffer_metadata :: proc() -> (handle: Handle, metadata: ^_Buffer_Metadata, res: Result) {
	sync.guard(&_buffers_mutex)

	handle = hm.add(&_buffers, _Buffer_Metadata {}) or_return
	metadata_ok: bool
	metadata, metadata_ok = hm.get(&_buffers, handle)
	assert(metadata_ok)

	return
}

_remove_buffer_metadata :: proc(handle: Handle) {
	sync.guard(&_buffers_mutex)

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
