package vicixdev_gfx

import "base:runtime"
import "core:mem"
import "core:sync"
import avl "core:container/avl"
import hm "core:container/handle_map"

// Memory types used to control resource placement and access.
Memory :: enum {
	// General-purpose memory.
	Default,

	// Memory accessible only by the device.
	Private,

	// Memory optimized for reading data back from the device.
	Readback,

	// Memory optimized for transfering data to the device.
	Staging,
}

_Buffer	:: distinct Handle

// Used internally to pass data about an address.
_Address_Info :: struct {
	buffer:		_Buffer,

	base:		uintptr,
	offset:		uintptr,
	remaining_size:	uintptr,
	address:	uintptr,

	is_cpu_address:	bool,
}

_Buffer_Metadata :: struct {
	handle:		_Buffer,

	memory_type:	Memory,
	size:		int,

	cpu_address:	uintptr,
	gpu_address:	uintptr,

	using platform: struct #raw_union {
		m3:	_m3_Buffer_Metadata,
		vk:	_vk_Buffer_Metadata,
	},
}

_buffers:	hm.Dynamic_Handle_Map(_Buffer_Metadata, _Buffer)
_buffers_mutex:	sync.RW_Mutex

_Address_Range :: struct {
	start:	uintptr,
	end:	uintptr,
}
_Address_Map_Node :: struct {
	address:	_Address_Range,
	buffer:		_Buffer,
	is_cpu_address:	bool,
}
_address_map:		avl.Tree(_Address_Map_Node)
_address_map_mutex:	sync.RW_Mutex

/*
Allocates a gpu buffer of the specified memory type.

The size of the allocation must be >= `device_info.limits.min_allocation_size` bytes and be a multiple of
`device_info.limits.allocation_alignment`. Sizes not adhering with these requirements will be adjusted.

Inputs:
- type: The memory type.
- size: The size of the allocation.

Returns:
- If `type` != .Private, a dereferenceable pointer containing the Cpu Virtual Mapped Address (CVMA) of the allocated
buffer.
- If `type` == .Private, a non-dereferenceable pointer containing the Gpu Virtual Address (GVA) of the allocated
buffer.
*/
alloc :: proc(type: Memory, size: int, location := #caller_location) -> (address: rawptr, res: Result) {

	_vl_alloc(type, size, location) or_return

	size := size
	if size < _device_info.limits.min_allocation_size {
		size = _device_info.limits.min_allocation_size
	}

	if !_is_aligned(cast(uintptr)size, _device_info.limits.allocation_alignment) {
		size = mem.align_forward_int(size, _device_info.limits.allocation_alignment)
	}

	handle, metadata := _add_buffer_metadata() or_return
	defer if res != nil do _remove_buffer_metadata(handle, metadata)

	metadata.size		= size
	metadata.memory_type	= type

	when TARGET_API == .Vulkan {
		res = _vk_alloc(metadata, type, size)
	} else when TARGET_API == .Metal_3 {
		res = _m3_alloc(metadata, type, size)
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

	_register_address_ranges(metadata) or_return

	if metadata.memory_type == .Private {
		return cast(rawptr)metadata.gpu_address, nil
	} else {
		return cast(rawptr)metadata.cpu_address, nil
	}
}

/*
Releases a gpu allocation.
*/
dealloc :: proc(address: rawptr, location := #caller_location) {

	address_info, address_res := _address_info_of(address)
	_check_address_info(address_res, address, location)
	if address_res != nil do return

	metadata, metadata_res := _metadata_of(address_info.buffer)
	assert(metadata_res == nil)

	if _vl_dealloc(address, address_info, location) != nil do return

	when TARGET_API == .Vulkan {
		_vk_dealloc(metadata)
	} else when TARGET_API == .Metal_3 {
		_m3_dealloc(metadata)
	}

	_remove_buffer_metadata(address_info.buffer, metadata)
}

/*
Returns the Gpu Virtual Address (GVA) of a given Cpu Mapped Virtual Address (CMVA).
*/
gpu_address_of :: proc(address: rawptr, location := #caller_location) -> (gpu_address: uintptr, res: Result) {
	address_info, address_res := _address_info_of(address)
	_check_address_info(address_res, address, location) or_return

	_vl_gpu_address_of(location) or_return

	if !address_info.is_cpu_address {
		return address_info.address, nil
	} else {
		metadata, metadata_res := _metadata_of(address_info.buffer)
		assert(metadata_res == nil)

		return metadata.gpu_address + address_info.offset, nil
	}
}

/*
Labels an allocation.
*/
label_buffer :: proc(address: rawptr, label: string, location := #caller_location) -> Result {
	address_info, address_res := _address_info_of(address)
	_check_address_info(address_res, address, location) or_return

	metadata, metadata_res := _metadata_of(address_info.buffer)
	assert(metadata_res == nil)

	_vl_label_buffer(address, address_info, location) or_return

	res: Result
	when TARGET_API == .Vulkan {
		res = _vk_label_buffer(metadata, label)
	} else when TARGET_API == .Metal_3 {
		res = _m3_label_buffer(metadata, label)
	}

	_check_generic_backend_error(res, location) or_return

	return nil
}

_dealloc_from_handle :: proc(buffer: _Buffer, location := #caller_location) {
	metadata, metadata_res := _metadata_of(buffer)
	assert(metadata_res == nil)

	when TARGET_API == .Vulkan {
		_vk_dealloc(metadata)
	} else when TARGET_API == .Metal_3 {
		_m3_dealloc(metadata)
	}

	_remove_buffer_metadata(buffer, metadata)
}

_check_address_info :: proc(result: Result, address: rawptr, location: runtime.Source_Code_Location) -> Result {
	_check_result(
		result,
		.Warning,
		"Invalid address",
		"The address 0x%x does not reference any valid allocation.",
		address,
		location=location,
	) or_return
	return nil
}

_to_gpu_address :: proc(address_info: _Address_Info) -> (address: uintptr, res: Result) {
	if !address_info.is_cpu_address {
		return address_info.address, nil
	} else {
		metadata := _metadata_of(address_info.buffer) or_return

		return metadata.gpu_address + address_info.offset, nil
	}
}

_buffer_metadata_of :: proc(buffer: _Buffer) -> (metadata: ^_Buffer_Metadata, res: Result) {
	sync.shared_guard(&_buffers_mutex)

	metadata_ok: bool
	metadata, metadata_ok = hm.get(&_buffers, buffer)
	if !metadata_ok {
		return nil, .Invalid_Buffer
	}
	
	return metadata, nil
}

_add_buffer_metadata :: proc() -> (buffer: _Buffer, metadata: ^_Buffer_Metadata, res: Result) {
	sync.guard(&_buffers_mutex)

	buffer = hm.add(&_buffers, _Buffer_Metadata {}) or_return
	metadata_ok: bool
	metadata, metadata_ok = hm.get(&_buffers, buffer)
	assert(metadata_ok)

	return
}

_remove_buffer_metadata :: proc(buffer: _Buffer, metadata: ^_Buffer_Metadata) {
	if sync.guard(&_address_map_mutex) {
		gpu_address_range := _Address_Range {
			start	= metadata.gpu_address,
			end	= metadata.gpu_address,
		}
		gpu_address_node := _Address_Map_Node {
			address	= gpu_address_range,
		}

		did_remove := avl.remove_value(&_address_map, gpu_address_node, false)
		assert(did_remove, "Could not find the node of a gpu address range.")

		if metadata.memory_type != .Private {
			cpu_address_range := _Address_Range {
				start	= metadata.cpu_address,
				end	= metadata.cpu_address,
			}
			cpu_address_node := _Address_Map_Node {
				address	= cpu_address_range,
			}

			did_remove = avl.remove_value(&_address_map, cpu_address_node, false)
			assert(did_remove, "Could not find the node of a cpu address range.")
		}

		// NOTE: This is the only point in the codebase where the mutexes are nested. Thus this should be fine.
		if sync.guard(&_buffers_mutex) {
			hm.remove(&_buffers, buffer)
		}
	}

}

_register_address_ranges :: proc(metadata: ^_Buffer_Metadata) -> Result {
	if sync.guard(&_address_map_mutex) {
		_register_address_range(metadata.gpu_address, metadata.size, metadata.handle, false) or_return

		if metadata.memory_type != .Private {
			_register_address_range(metadata.cpu_address, metadata.size, metadata.handle, true) or_return
		}
	}

	return nil
}

_register_address_range :: proc(base_ptr: uintptr, length: int, buffer: _Buffer, is_cpu_address: bool) -> Result {
	address_range := _Address_Range {
		start		= base_ptr,
		end		= base_ptr + cast(uintptr)length,
	}
	node := _Address_Map_Node {
		address		= address_range,
		buffer		= buffer,
		is_cpu_address	= is_cpu_address,
	}

	_, inserted := avl.find_or_insert(&_address_map, node) or_return
	assert(inserted, "The registered address is already present in the address map.")

	return nil
}

_address_info_of :: proc(address: rawptr) -> (info: _Address_Info, res: Result) {
	
	address_range := _Address_Range {
		start	= cast(uintptr)address,
		end	= cast(uintptr)address,
	}
	needle := _Address_Map_Node {
		address = address_range,
	}

	if sync.shared_guard(&_address_map_mutex) {
		node := avl.find(&_address_map, needle)

		if node == nil {
			return {}, .Invalid_Buffer
		}

		info.address		= cast(uintptr)address
		info.buffer		= node.value.buffer
		info.base		= node.value.address.start
		info.offset		= info.address - info.base
		info.remaining_size	= node.value.address.end - info.address
		info.is_cpu_address	= node.value.is_cpu_address
	}

	return
}

_is_aligned :: proc(p: uintptr, #any_int align: int) -> bool {
	return (p & (uintptr(align) - 1)) == 0
}

// NOTE: The avl tree implementation always puts the seached value as the first parameter and the current node as the
//	second parameter. This is a bit of a hack, but it works.
_compare_address_map_nodes :: proc(needle: _Address_Map_Node, node: _Address_Map_Node) -> avl.Ordering {
	if node.address.start <= needle.address.start && node.address.end > needle.address.end {
		return .Equal
	} else if node.address.start > needle.address.start {
		return .Greater
	} else {
		return .Less
	}
}

_vl_alloc :: proc(
	type:		Memory,
	size:		int,
	location:	runtime.Source_Code_Location,
) -> Result {
	
	when !ENABLE_VALIDATION do return nil

	_check_device_selected(location) or_return

	_check_generic_condition(
		size >= _device_info.limits.min_allocation_size,
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
	_check_generic_condition(
		_is_aligned(cast(uintptr)size, _device_info.limits.allocation_alignment),
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

	return nil
}

_vl_dealloc :: proc(address: rawptr, address_info: _Address_Info, location: runtime.Source_Code_Location) -> Result {
	when !ENABLE_VALIDATION do return nil

	_check_device_selected(location) or_return

	_check_generic_condition(
		address_info.offset == 0,
		.Warning,
		"Freeing address with offset",
		"The provided address 0x%x references an allocation with base address 0x%x. `gfx::dealloc` would " +
		"require every allocation to be released referencing its base address. The deallocation will still " +
		"complete.",
		address,
		address_info.base,
		location=location,
	)

	return nil
}

_vl_gpu_address_of :: proc(location: runtime.Source_Code_Location) -> Result {
	when !ENABLE_VALIDATION do return nil

	_check_device_selected(location) or_return

	return nil
}

_vl_label_buffer :: proc(
	address: rawptr,
	address_info: _Address_Info,
	location: runtime.Source_Code_Location,
) -> Result {

	when !ENABLE_VALIDATION do return nil

	_check_device_selected(location) or_return

	_check_generic_condition(
		address_info.offset == 0,
		.Warning,
		"Labeling address with offset",
		"The provided address 0x%x references an allocation with base address 0x%x. `gfx::label_buffer`" +
		"would require every allocation to be labeled referencing its base address. The labeling will still " +
		"complete.",
		address,
		address_info.base,
		location=location,
	)

	return nil
}

