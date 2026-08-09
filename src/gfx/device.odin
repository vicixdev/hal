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
_device_is_being_initialized:	bool

enumerate_devices :: proc(
	location := #caller_location,
) -> (available_devices: []Device_Info, res: Result) {
	_check_initialized(location) or_return

	if _available_devices != nil {
		return _available_devices, nil
	}

	when TARGET_API == .Vulkan {
		_available_devices, res = vk_enumerate_devices(_global_allocator)
	} else when TARGET_API == .Metal_3 {
		_available_devices, res = m3_enumerate_devices(_global_allocator)
	}

	_check_generic_backend_error(res, location) or_return

	return _available_devices, nil
}

select_device :: proc(device: Device_Id, location := #caller_location) -> (res: Result) {
	_check_initialized(location) or_return

	enumerate_devices(location) or_return

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

	_device_is_being_initialized = true
	defer _device_is_being_initialized = false

	when TARGET_API == .Vulkan {
		res = vk_select_device(device)
		_check_generic_backend_error(res, location) or_return

	} else when TARGET_API == .Metal_3 {
		res = m3_select_device(device)
		_check_generic_backend_error(res, location) or_return
	}

	_device_info = &_available_devices[device]
	ensure(_init_queues() == nil, "If the device got selected, then the queue setup should not fail.")

	_is_device_selected = true

	return nil
}

_check_device_selected :: proc(location: runtime.Source_Code_Location) -> Result {
	_check_initialized(location) or_return
	_check_condition(
		_is_device_selected || _device_is_being_initialized,
		.Device_Not_Selected,
		.Error,
		"Device not selected",
		"A device has not yet been selected. Please call `gfx::select_device`.",
		location=location,
	) or_return
	return nil
}

