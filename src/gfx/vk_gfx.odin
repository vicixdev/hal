package gfx

import "base:runtime"
import "base:intrinsics"
import "core:dynlib"
import "core:log"
import vmem "core:mem/virtual"
import vk "vendor:vulkan"

when ODIN_OS == .Linux {
	vk_VULKAN_LOADER_PATH :: "/lib64/libvulkan.so"
} else when ODIN_OS == .Darwin {
	vk_VULKAN_LOADER_PATH :: "/opt/homebrew/lib/libvulkan.dylib"
} else {
	#panic("Unsupported vulkan target. Only linux is currently supported.")
}

vk_global_arena:		vmem.Arena
vk_global_allocator:		runtime.Allocator

vk_loader_lib:			dynlib.Library

vk_debug_messenger:		vk.DebugUtilsMessengerEXT
vk_debug_messenger_descriptor:	vk.DebugUtilsMessengerCreateInfoEXT

vk_instance_layers:		[]vk.LayerProperties
vk_instance_extensions:		[]vk.ExtensionProperties
vk_enabled_instance_layers:	[dynamic; 8]cstring
vk_enabled_instance_extensions:	[dynamic; 8]cstring
vk_instance:			vk.Instance
vk_has_validation:		bool
vk_user_logger:			log.Logger

vk_load_instance_procs :: proc() {
	loader_path := _settings.vk.loader_path
	if loader_path == "" {
		loader_path = vk_VULKAN_LOADER_PATH
	}

	vk_lib, lib_ok := dynlib.load_library(loader_path)
	assert(lib_ok, "Could not find the vulkan loader library.")
	vk_loader_lib = vk_lib

	vk_get_proc, get_proc_ok := dynlib.symbol_address(vk_loader_lib, "vkGetInstanceProcAddr")
	assert(get_proc_ok, "Could not acquire the vkGetInstanceProc address from the vulkan loader.")

	vk.load_proc_addresses(vk_get_proc)
}

vk_try_use_instance_layer :: proc(layer: cstring) -> (found_layer: bool) {
	for &layer_properties in vk_instance_layers {
		layer_name := cast(cstring)&layer_properties.layerName[0]

		if layer_name == layer {
			found_layer = true
			break
		}
	}

	if found_layer {
		append(&vk_enabled_instance_layers, layer)
	}

	return
}

vk_try_use_instance_extension :: proc(extension: cstring) -> (found_extension: bool) {
	for &extension_properties in vk_instance_extensions {
		layer_name := cast(cstring)&extension_properties.extensionName[0]

		if layer_name == extension {
			found_extension = true
			break
		}
	}

	if found_extension {
		append(&vk_enabled_instance_extensions, extension)
	}

	return
}

vk_init_instance :: proc() {
	vk_has_validation = ODIN_DEBUG

	instance_layer_count: u32
	vk_call(vk.EnumerateInstanceLayerProperties(&instance_layer_count, nil))
	vk_instance_layers = make([]vk.LayerProperties, instance_layer_count, vk_global_allocator)
	vk_call(vk.EnumerateInstanceLayerProperties(&instance_layer_count, raw_data(vk_instance_layers)))

	log.debugf("Available instance layers:")
	for &layer in vk_instance_layers {
		log.debugf(
			"\t- %s: %s",
			cast(cstring)&layer.layerName[0],
			cast(cstring)&layer.description[0],
		)
	}

	instance_extension_count: u32 
	vk_call(vk.EnumerateInstanceExtensionProperties(nil, &instance_extension_count, nil))
	vk_instance_extensions = make([]vk.ExtensionProperties, instance_extension_count, vk_global_allocator)
	vk_call(vk.EnumerateInstanceExtensionProperties(nil, &instance_extension_count, raw_data(vk_instance_extensions)))

	log.debugf("Available instance extensions:")
	for &extension in vk_instance_extensions {
		log.debugf(
			"\t- %s",
			cast(cstring)&extension.extensionName[0],
		)
	}

	has_validation_layer := vk_try_use_instance_layer("VK_LAYER_KHRONOS_validation")
	log.debugf("Creating vulkan instance with layers: %v.", vk_enabled_instance_layers)

	when ODIN_OS == .Darwin {
		ensure(
			vk_try_use_instance_extension("VK_KHR_portability_enumeration"),
			"Vulkan on macOS does not expose the VK_KHR_portability_enumeration extension. Broken install?",
		)
	}
	has_debug_utils := vk_try_use_instance_extension("VK_EXT_debug_utils")
	log.debugf("Creating vulkan instance with extensions: %v.", vk_enabled_instance_extensions)

	if !has_debug_utils || !has_validation_layer {
		log.warn("The instance does not meet the requirements to enable validation.")
		vk_has_validation = false
	}

	instance_desc := vk.InstanceCreateInfo {
		sType			= .INSTANCE_CREATE_INFO,
		enabledLayerCount	= cast(u32)len(vk_enabled_instance_layers),
		ppEnabledLayerNames	= raw_data(vk_enabled_instance_layers[:]),
		enabledExtensionCount	= cast(u32)len(vk_enabled_instance_extensions),
		ppEnabledExtensionNames	= raw_data(vk_enabled_instance_extensions[:]),
		flags			= {} when ODIN_OS != .Darwin else { .ENUMERATE_PORTABILITY_KHR },
		pApplicationInfo	= &{
			sType			= .APPLICATION_INFO,
			pApplicationName	= "Hal Application",
			pEngineName		= "Hal",
			engineVersion		= vk.MAKE_VERSION(0, 1, 0),
			apiVersion		= vk.MAKE_VERSION(1, 3, 0),
		},
	}
	if has_debug_utils {
		vk_link(&instance_desc, &vk_debug_messenger_descriptor)
	}
	when ODIN_OS == .Darwin && ODIN_DEBUG {
		export_info := vk.ExportMetalObjectCreateInfoEXT {
			sType			= .EXPORT_METAL_OBJECT_CREATE_INFO_EXT,
			exportObjectType	= { .METAL_DEVICE },
		}
		vk_link(&instance_desc, &export_info)
	}

	vk_call(vk.CreateInstance(&instance_desc, nil, &vk_instance))
	vk.load_proc_addresses(vk_instance)

	if vk_has_validation {
		vk_call(vk.CreateDebugUtilsMessengerEXT(vk_instance, &vk_debug_messenger_descriptor, nil, &vk_debug_messenger))
	}

	version: u32
	vk.EnumerateInstanceVersion(&version)
	log.debugf("Using Vulkan 1.3.0 (available %d.%d.%d).", vk.VERSION_MAJOR(version), vk.VERSION_MINOR(version), vk.VERSION_PATCH(version))
}

vk_prepare_debug_messenger :: proc() {
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
		context.logger = vk_user_logger

		logging_proc(
			"[VULKAN - %v] %s - %s",
			actual_type,
			data.pMessageIdName,
			data.pMessage,
		)

		return true
	}

	vk_user_logger = context.logger

	vk_debug_messenger_descriptor = vk.DebugUtilsMessengerCreateInfoEXT {
		sType		= .DEBUG_UTILS_MESSENGER_CREATE_INFO_EXT,
		messageSeverity	= { .WARNING, .ERROR },
		messageType	= { .GENERAL, .VALIDATION, .PERFORMANCE },
		pfnUserCallback	= messenger_callback,
	}
}

vk_init :: proc() {

	arena_err := vmem.arena_init_growing(&vk_global_arena)
	assert(arena_err == .None, "Could not create a virtual arena for global allocations.")

	vk_global_allocator = vmem.arena_allocator(&vk_global_arena)

	vk_load_instance_procs()
	vk_prepare_debug_messenger()
	vk_init_instance()
}

vk_fini :: proc() {
	when ODIN_OS == .Darwin && ODIN_DEBUG {
		m3_end_tracing()
	}

	vk.DestroyDevice(vk_device, nil)

	if vk_has_validation {
		vk.DestroyDebugUtilsMessengerEXT(vk_instance, vk_debug_messenger, nil)
	}
	vk.DestroyInstance(vk_instance, nil)

	dynlib.unload_library(vk_loader_lib)
}


vk_start_command_encoding :: proc() -> (handle: Command_Buffer, res: Result) {
	return
}

vk_syncronize_buffers :: proc(cb: Command_Buffer) {}
vk_mem_copy :: proc(cb: Command_Buffer, destination: Buffer, source: Buffer, size: int) -> Result {
	return nil
}

vk_set_pipeline :: proc(cb: Command_Buffer, pipeline: Pipeline) -> Result {
	return nil
}
vk_set_indirect_buffer_pool :: proc(cb: Command_Buffer, buffers: []Buffer) -> Result {
	return nil
}
vk_set_texture_pool :: proc(cb: Command_Buffer, textures: []View) -> Result {
	return nil
}
vk_set_buffer :: proc(
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
vk_dispatch :: proc(cb: Command_Buffer, groups: [3]int) -> Result {
	return nil
}

vk_generate_mipmaps :: proc(cb: Command_Buffer, texture: Texture) -> Result {
	return nil
}

vk_begin_renderpass :: proc(
	cb: Command_Buffer,
	/* ... */
) {}
vk_end_renderpass :: proc(cb: Command_Buffer) {}
vk_draw :: proc(
	cb: Command_Buffer,
	vertices: int,
	instances: int,
	vertex_arg: Buffer,
	fragment_arg: Buffer,
	base_vertex: int,
) {}
vk_draw_indexed :: proc(
	cb: Command_Buffer,
	indices: int,
	instances: int,
	index_buffer: Buffer,
	vertex_arg: Buffer,
	fragment_arg: Buffer,
	base_index: int,
) {}

vk_barrier :: proc(cb: Command_Buffer, before: Stages, after: Stages) -> Result {
	return nil
}
// wait: proc(cb: Command_Buffer)
// signal: proc(cb: Command_Buffer)

vk_submit :: proc(cb: Command_Buffer) -> Result {
	return nil
}

vk_call :: proc(res: vk.Result, expr := #caller_expression, loc := #caller_location) {
	when ODIN_DEBUG {
		if res == .SUCCESS {
			return
		}

		log.panicf("Vulkan error (%s).", expr)
	} else {
		assert(res == .SUCCESS, "Vulkan error.", loc)
	}
}

vk_link :: proc(a: ^$T, b: ^$U)
	where intrinsics.type_has_field(T, "pNext"),
		intrinsics.type_has_field(U, "pNext") {

	old_link := a.pNext
	a.pNext = b

	b.pNext = old_link
}

