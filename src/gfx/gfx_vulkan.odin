#+build linux
package gfx

import "base:runtime"
import "core:dynlib"
import "core:log"
import vmem "core:mem/virtual"
import vk "vendor:vulkan"

when ODIN_OS == .Linux {
	VULKAN_PATH :: "/lib64/libvulkan.so"
} else {
	#panic("Unsupported vulkan target. Only linux is currently supported.")
}

_global_arena:		vmem.Arena
_global_allocator:	runtime.Allocator

_vk_loader_lib:		dynlib.Library

_debug_messenger:		vk.DebugUtilsMessengerEXT
_debug_messenger_descriptor:	vk.DebugUtilsMessengerCreateInfoEXT

_instance_layers:		[]vk.LayerProperties
_instance_extensions:		[]vk.ExtensionProperties
_enabled_instance_layers:	[]cstring
_enabled_instance_extensions:	[]cstring
_instance:			vk.Instance
_has_validation:		bool
_user_logger:			log.Logger

_physical_devices:			[dynamic; 8]vk.PhysicalDevice
_physical_device_properties:		[dynamic; 8]vk.PhysicalDeviceProperties2
_physical_device_buffer_features:	[dynamic; 8]vk.PhysicalDeviceBufferDeviceAddressFeatures
_physical_device_features:		[dynamic; 8]vk.PhysicalDeviceFeatures2

_physical_device:		vk.PhysicalDevice
_physical_device_idx:		int
_queue_families:		[]vk.QueueFamilyProperties2
_transfer_queue_family:		int
_compute_queue_family:		int
_graphics_queue_family:		int

_device:			vk.Device

_load_instance_procs :: proc() {
	vk_lib, lib_ok := dynlib.load_library("/lib/libvulkan.so")
	assert(lib_ok, "Could not find the vulkan loader library (expected at " + VULKAN_PATH + ").")
	_vk_loader_lib = vk_lib

	vk_get_proc, get_proc_ok := dynlib.symbol_address(_vk_loader_lib, "vkGetInstanceProcAddr")
	assert(get_proc_ok, "Could not acquire the vkGetInstanceProc address from the vulkan loader.")

	vk.load_proc_addresses(vk_get_proc)
}

_init_instance :: proc() {
	_has_validation = ODIN_DEBUG

	instance_layer_count: u32
	_call(vk.EnumerateInstanceLayerProperties(&instance_layer_count, nil))
	_instance_layers = make([]vk.LayerProperties, instance_layer_count, _global_allocator)
	_call(vk.EnumerateInstanceLayerProperties(&instance_layer_count, raw_data(_instance_layers)))

	log.debugf("Available instance layers:")
	for &layer in _instance_layers {
		log.debugf(
			"\t- %s: %s",
			cast(cstring)&layer.layerName[0],
			cast(cstring)&layer.description[0],
		)
	}

	instance_extension_count: u32 
	_call(vk.EnumerateInstanceExtensionProperties(nil, &instance_extension_count, nil))
	_instance_extensions = make([]vk.ExtensionProperties, instance_extension_count, _global_allocator)
	_call(vk.EnumerateInstanceExtensionProperties(nil, &instance_extension_count, raw_data(_instance_extensions)))

	log.debugf("Available instance extensions:")
	for &extension in _instance_extensions {
		log.debugf(
			"\t- %s",
			cast(cstring)&extension.extensionName[0],
		)
	}

	has_validation_layer := false
	if _has_validation do for &layer in _instance_layers {
		layer_name := cast(cstring)&layer.layerName[0]

		if layer_name == "VK_LAYER_KHRONOS_validation" {
			has_validation_layer = true
			break
		}
	}

	if has_validation_layer {
		_enabled_instance_layers = { "VK_LAYER_KHRONOS_validation" }
	}
	log.debugf("Creating vulkan instance with layers: %v.", _enabled_instance_layers)

	has_debug_utils := false
	if _has_validation do for &extension in _instance_extensions {
		extension_name := cast(cstring)&extension.extensionName[0]

		if extension_name == "VK_EXT_debug_utils" {
			has_debug_utils = true
			break
		}
	}

	if has_debug_utils {
		_enabled_instance_extensions = { "VK_EXT_debug_utils" }
	}
	log.debugf("Creating vulkan instance with extensions: %v.", _enabled_instance_extensions)

	if !has_debug_utils || !has_validation_layer {
		log.warn("The instance does not meet the requirements to enable validation.")
		_has_validation = false
	}

	instance_desc := vk.InstanceCreateInfo {
		sType			= .INSTANCE_CREATE_INFO,
		enabledLayerCount	= has_validation_layer ? 1 : 0,
		ppEnabledLayerNames	= &_enabled_instance_layers[0],
		enabledExtensionCount	= has_debug_utils ? 1 : 0,
		ppEnabledExtensionNames	= &_enabled_instance_extensions[0],
		pApplicationInfo	= &{
			sType			= .APPLICATION_INFO,
			pApplicationName	= "Hal Application",
			pEngineName		= "Hal",
			engineVersion		= vk.MAKE_VERSION(0, 1, 0),
			apiVersion		= vk.MAKE_VERSION(1, 3, 0),
		},
		pNext			= has_debug_utils ? &_debug_messenger_descriptor : nil,
	}

	_call(vk.CreateInstance(&instance_desc, nil, &_instance))
	vk.load_proc_addresses(_instance)

	if _has_validation {
		_call(vk.CreateDebugUtilsMessengerEXT(_instance, &_debug_messenger_descriptor, nil, &_debug_messenger))
	}
}

_prepare_debug_messenger :: proc() {
	messenger_callback :: proc "system" (
		message_severity: vk.DebugUtilsMessageSeverityFlagsEXT,
		message_types: vk.DebugUtilsMessageTypeFlagsEXT,
		data: ^vk.DebugUtilsMessengerCallbackDataEXT,
		userdata: rawptr,
	) -> b32 {
		actual_severity := vk.DebugUtilsMessageSeverityFlagEXT.VERBOSE
		if .INFO in message_severity {
			actual_severity = .INFO
		}
		if .WARNING in message_severity {
			actual_severity = .WARNING
		}
		if .ERROR in message_severity {
			actual_severity = .ERROR
		}

		actual_type := vk.DebugUtilsMessageTypeFlagEXT.GENERAL
		if .VALIDATION in message_types {
			actual_type = .VALIDATION
		}
		if .PERFORMANCE in message_types {
			actual_type = .PERFORMANCE
		}

		logging_proc: type_of(log.infof)
		switch actual_severity {
		case .VERBOSE:	logging_proc = log.debugf
		case .INFO:	logging_proc = log.infof
		case .WARNING:	logging_proc = log.warnf
		case .ERROR:	logging_proc = log.errorf
		}

		context = runtime.default_context()
		context.logger = _user_logger

		logging_proc(
			"[VULKAN - %v] %s - %s",
			actual_type,
			data.pMessageIdName,
			data.pMessage,
		)

		return true
	}

	_user_logger = context.logger

	_debug_messenger_descriptor = vk.DebugUtilsMessengerCreateInfoEXT {
		sType		= .DEBUG_UTILS_MESSENGER_CREATE_INFO_EXT,
		messageSeverity	= { .WARNING, .ERROR },
		messageType	= { .GENERAL, .VALIDATION, .PERFORMANCE },
		pfnUserCallback	= messenger_callback,
	}
}

_select_physical_device :: proc() {
	physical_device_count: u32
	_call(vk.EnumeratePhysicalDevices(_instance, &physical_device_count, nil))	

	resize(&_physical_devices, physical_device_count)
	resize(&_physical_device_properties, physical_device_count)
	resize(&_physical_device_features, physical_device_count)
	resize(&_physical_device_buffer_features, physical_device_count)
	_call(vk.EnumeratePhysicalDevices(_instance, &physical_device_count, &_physical_devices[0]))	

	for device, i in _physical_devices {
		properties	:= &_physical_device_properties[i]
		features	:= &_physical_device_features[i]
		buffer_features	:= &_physical_device_buffer_features[i]

		properties.sType	= .PHYSICAL_DEVICE_PROPERTIES_2
		features.sType		= .PHYSICAL_DEVICE_FEATURES_2
		buffer_features.sType	= .PHYSICAL_DEVICE_BUFFER_DEVICE_ADDRESS_FEATURES
		features.pNext 		= buffer_features

		vk.GetPhysicalDeviceProperties2(device, properties)
		vk.GetPhysicalDeviceFeatures2(device, features)
	}

	log.debugf("Found available physical devices:")
	for &properties in _physical_device_properties {
		log.debugf(
			"\t- %s: %v",
			cast(cstring)&properties.properties.deviceName[0],
			properties.properties.deviceType,
		)
	}

	is_selected_device_integrated := true
	for device, i in _physical_devices {
		properties	:= &_physical_device_properties[i]
		buffer_features	:= &_physical_device_buffer_features[i]
		
		if !buffer_features.bufferDeviceAddress {
			continue
		}

		if !is_selected_device_integrated ||
			properties.properties.deviceType == .CPU ||
			properties.properties.deviceType == .VIRTUAL_GPU ||
			properties.properties.deviceType == .OTHER {

			continue
		}

		_physical_device = device
		_physical_device_idx = i

		is_selected_device_integrated = properties.properties.deviceType == .INTEGRATED_GPU
	}

	if _physical_device == nil {
		log.panicf("Could not find a suitable physical device.")
	}

	log.debugf(
		"Using physical device %s.",
		cast(cstring)&_physical_device_properties[_physical_device_idx].properties.deviceName[0],
	)
}

_find_queue_families :: proc() {
	queue_family_count: u32
	vk.GetPhysicalDeviceQueueFamilyProperties2(_physical_device, &queue_family_count, nil)

	_queue_families = make([]vk.QueueFamilyProperties2, queue_family_count, _global_allocator)
	for &family in _queue_families {
		family.sType = .QUEUE_FAMILY_PROPERTIES_2
	}
	vk.GetPhysicalDeviceQueueFamilyProperties2(_physical_device, &queue_family_count, raw_data(_queue_families))
	
	transfer_ok, compute_ok, graphics_ok: bool

	// TODO: Better queue family selection
	for queue, i in _queue_families {
		if .TRANSFER in queue.queueFamilyProperties.queueFlags {
			_transfer_queue_family = i
			transfer_ok = true
		}
		if .COMPUTE in queue.queueFamilyProperties.queueFlags {
			_compute_queue_family = i
			compute_ok = true
		}
		if .GRAPHICS in queue.queueFamilyProperties.queueFlags {
			_graphics_queue_family = i
			graphics_ok = true
		}
	}

	if !transfer_ok || !compute_ok || !graphics_ok {
		log.panicf("Could not find a queue suitable every need.")
	}
}

_create_device :: proc() {
	// descriptor := vk.DeviceCreateInfo {
	// 	sType = .DEVICE_CREATE_INFO,
	// }

	// _device := vk.CreateDevice(_physical_device, )
}

_init :: proc() {

	arena_err := vmem.arena_init_growing(&_global_arena)
	assert(arena_err == .None, "Could not create a virtual arena for global allocations.")

	_global_allocator = vmem.arena_allocator(&_global_arena)


	_load_instance_procs()
	_prepare_debug_messenger()
	_init_instance()
	_select_physical_device()
	_find_queue_families()
}

_fini :: proc() {}

_alloc :: proc(type: Memory, size: int) -> (handle: Buffer, res: Result) {
	return
}
_dealloc :: proc(buffer: Buffer) {
	return
}
_gpu_reference_of :: proc(buffer: Buffer) -> (ref: GpuDataRef, res: Result) {
	return
}
_mark_as_modified :: proc(buffer: Buffer, length: int) {}
_label_buffer :: proc(buffer: Buffer, label: string) {}

_size_align_of :: proc(descriptor: Texture_Descriptor) -> (size: int, align: int, res: Result) {
	return
}
_create_texture :: proc(
	buffer: Buffer,
	descriptor: Texture_Descriptor,
) -> (
	handle: Texture,
	res: Result,
) {
	return
}
_destroy_texture :: proc(texture: Texture) {}
_label_texture :: proc(texture: Texture, label: string) {}

_create_default_view :: proc(texture: Texture) -> (handle: View, res: Result) {
	return
}
_create_view_with_descriptor :: proc(
	texture: Texture,
	descriptor: View_Descriptor,
) -> (
	handle: View,
	res: Result,
) {
	return
}
_label_view :: proc(view: View, label: string) {}

_create_library_from_bytes :: proc(bytes: []byte) -> (handle: Library, res: Result) {
	return
}
_create_library_from_file :: proc(path: string) -> (handle: Library, res: Result) {
	return
}

_create_compute_pipeline :: proc(
	library: Library,
	name: string,
	constants: []Constant,
	group_size: [3]int,
) -> (
	handle: Pipeline,
	res: Result,
) {
	return
}
_create_render_pipeline :: proc() -> (handle: Pipeline) {
	return
}

_start_command_encoding :: proc() -> (handle: Command_Buffer, res: Result) {
	return
}

_syncronize_buffers :: proc(cb: Command_Buffer) {}
_mem_copy :: proc(cb: Command_Buffer, destination: Buffer, source: Buffer, size: int) -> Result {
	return nil
}

_set_pipeline :: proc(cb: Command_Buffer, pipeline: Pipeline) -> Result {
	return nil
}
_set_indirect_buffer_pool :: proc(cb: Command_Buffer, buffers: []Buffer) -> Result {
	return nil
}
_set_texture_pool :: proc(cb: Command_Buffer, textures: []View) -> Result {
	return nil
}
_set_buffer :: proc(
	cb: Command_Buffer,
	buffer: Buffer,
	index: int,
	stage: Raster_Stage = .Compute,
) -> Result {
	return nil
}

// copy_buffer_to_texture: proc(cb: Command_Buffer, )
// copy_texture_to_buffer
// copy_texture_to_texture
_dispatch :: proc(cb: Command_Buffer, groups: [3]int) -> Result {
	return nil
}

_generate_mipmaps :: proc(cb: Command_Buffer, texture: Texture) -> Result {
	return nil
}

_begin_renderpass :: proc(
	cb: Command_Buffer,
	/* ... */
) {}
_end_renderpass :: proc(cb: Command_Buffer) {}
_draw :: proc(
	cb: Command_Buffer,
	vertices: int,
	instances: int,
	vertex_arg: Buffer,
	fragment_arg: Buffer,
	base_vertex: int,
) {}
_draw_indexed :: proc(
	cb: Command_Buffer,
	indices: int,
	instances: int,
	index_buffer: Buffer,
	vertex_arg: Buffer,
	fragment_arg: Buffer,
	base_index: int,
) {}

_barrier :: proc(cb: Command_Buffer, before: Stages, after: Stages) -> Result {
	return nil
}
// wait: proc(cb: Command_Buffer)
// signal: proc(cb: Command_Buffer)

_submit :: proc(cb: Command_Buffer) -> Result {
	return nil
}

_call :: proc(res: vk.Result, expr := #caller_expression, loc := #caller_location) {
	when ODIN_DEBUG {
		if res == .SUCCESS {
			return
		}

		log.panicf("Vulkan error (%s).", expr)
	} else {
		assert(res == .SUCCESS, "Vulkan error.", loc)
	}
}

