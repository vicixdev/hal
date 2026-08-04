package gfx

import "base:runtime"

Device_Id :: distinct u64

Device_Type :: enum {
	Integrated,
	Discrete,
	Other,
}

Device_Limits :: struct {
	// Minimum size for gpu allocations, in bytes.
	min_allocation_size:	int,
	// Required alignment for gpu allocations, in bytes.
	allocation_alignment:	int,
}

Device_Properties :: struct {
	// `.Default` and `.Readback` memory allocations reside on the device.
	//	NOTE: This only affects the gpu-access speed. The same code should work whether this is true or false.
	host_accessible_device_memory:	bool,

	// The device is fast at executing interleaved compute and render operations.
	fast_compute_render_interleaving:	bool,

	// Host and device memory accesses are automatically kept synchronized.
	//	If true, calls to `gfx::mark_as_modified` and `gfx::prepare_for_readback` are not required and ignored.
	//	If false, the user must manually synchronize the buffers using the aforementioned functions.
	coherent_memory:		bool,

	// The priority queue for data transfer operations is available.
	transfer_queue:			bool,
}

Device_Info :: struct {
	id:		Device_Id,
	name:		string,
	type:		Device_Type,
	properties:	Device_Properties,
	limits:		Device_Limits,

	_platform:	struct #raw_union {
		m3:	m3_Device_Info,
		vk:	vk_Device_Info,
	},
}

_available_devices:	[]Device_Info

_device_info:		^Device_Info
_selected_device:	Device_Id
_is_device_selected:	bool

enumerate_devices :: proc(
	location := #caller_location,
) -> (available_devices: []Device_Info, res: Result) {
	_check_initialized(location) or_return

	if _available_devices != nil {
		return _available_devices, nil
	}

	when TARGET_API == .Vulkan {
		_available_devices = vk_enumerate_devices(context.allocator) or_return
	} else when TARGET_API == .Metal_3 {
		_available_devices = m3_enumerate_devices(context.allocator) or_return
	}

	return _available_devices, nil
}

select_device :: proc(device: Device_Id, location := #caller_location) -> Result {
	_check_initialized(location) or_return

	enumerate_devices() or_return

	_check_condition(
		cast(uint)device < len(_available_devices),
		.Invalid_Device,
		.Error,
		"Invalid device id",
		"The user is requesting device %d, while only %d are available",
		device,
		len(_available_devices),
		location=location,
	) or_return

	when TARGET_API == .Vulkan {
		vk_select_device(device) or_return
	} else when TARGET_API == .Metal_3 {
		m3_select_device(device) or_return
	}

	_is_device_selected = true
	_device_info = &_available_devices[device]

	return nil
}

_check_device_selected :: proc(location: runtime.Source_Code_Location) -> Result {
	_check_initialized(location) or_return
	_check_condition(
		_is_device_selected,
		.Device_Not_Selected,
		.Error,
		"Device not selected",
		"A device has not yet been selected. Please call `gfx::select_device`.",
		location=location,
	) or_return
	return nil
}

