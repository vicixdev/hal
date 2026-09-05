package vicixdev_gfx

import "base:runtime"
import "base:intrinsics"
import "core:dynlib"
import "core:strings"
import "core:log"
import "core:os"
import vk "vendor:vulkan"

when ODIN_OS == .Linux {
	vk_VULKAN_LOADER_PATHS :: []string {
		"./libvulkan.so",
		"libvulkan.so",
		"/lib64/libvulkan.so",
	}
} else when ODIN_OS == .Darwin {
	vk_VULKAN_LOADER_PATHS :: []string{
		"./libvulkan.dylib",
		"../Frameworks/libvulkan.dylib",
		"./demo/env/macOS/lib/libvulkan.dylib",
		"libvulkan.dylib",
		"/opt/homebrew/lib/libvulkan.dylib",
	}
} else when ODIN_OS == .Windows {
	vk_VULKAN_LOADER_PATHS :: []string{
		"./vulkan-1.dll",
		"vulkan-1.dll",
		"C:/Windows/System32/vulkan-1.dll",
	}
} else {
	#panic("Unsupported vulkan target.")
}

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

vk_supports_metal_surfaces:	bool
vk_supports_win32_surfaces:	bool
vk_supports_wayland_surfaces:	bool
vk_supports_xlib_surfaces:	bool

vk_try_loader_path :: proc(loader_path: string) -> bool {
	vk_lib := dynlib.load_library(loader_path) or_return
	vk_loader_lib = vk_lib

	vk_get_proc := dynlib.symbol_address(vk_loader_lib, "vkGetInstanceProcAddr") or_return
	vk.load_proc_addresses(vk_get_proc)
	
	return true
}

vk_load_instance_procs :: proc() -> Result {
	user_path := _settings.vk.loader_path
	if user_path == "" {
		if vk_try_loader_path(user_path) {
			return nil
		}
	}

	for loader_path in vk_VULKAN_LOADER_PATHS {
		if vk_try_loader_path(loader_path) {
			return nil
		}
	}

	return .Not_Initialized
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

vk_init_instance :: proc() -> Result {
	vk_has_validation = ENABLE_VALIDATION

	instance_layer_count: u32
	vk_call(vk.EnumerateInstanceLayerProperties(&instance_layer_count, nil)) or_return
	vk_instance_layers = make([]vk.LayerProperties, instance_layer_count, _global_allocator)
	vk_call(vk.EnumerateInstanceLayerProperties(&instance_layer_count, raw_data(vk_instance_layers))) or_return

	log.debugf("Available instance layers:")
	for &layer in vk_instance_layers {
		log.debugf(
			"\t- %s: %s",
			cast(cstring)&layer.layerName[0],
			cast(cstring)&layer.description[0],
		)
	}

	instance_extension_count: u32 
	vk_call(vk.EnumerateInstanceExtensionProperties(nil, &instance_extension_count, nil)) or_return
	vk_instance_extensions = make([]vk.ExtensionProperties, instance_extension_count, _global_allocator)
	vk_call(vk.EnumerateInstanceExtensionProperties(nil, &instance_extension_count, raw_data(vk_instance_extensions))) or_return

	log.debugf("Available instance extensions:")
	for &extension in vk_instance_extensions {
		log.debugf(
			"\t- %s",
			cast(cstring)&extension.extensionName[0],
		)
	}

	has_validation_layer: bool
	when ENABLE_VALIDATION {
		has_validation_layer = vk_try_use_instance_layer("VK_LAYER_KHRONOS_validation")
	}
	log.debugf("Creating vulkan instance with layers: %v.", vk_enabled_instance_layers)

	when ODIN_OS == .Darwin {
		vk_try_use_instance_extension("VK_KHR_portability_enumeration")
	}
	has_debug_utils := vk_try_use_instance_extension("VK_EXT_debug_utils")

	supports_surfaces := vk_try_use_instance_extension("VK_KHR_surface")
	ensure(supports_surfaces, "The vulkan instace does not support presentation. Headless rendering is not yet supported.")
	when ODIN_OS == .Darwin {
		vk_supports_metal_surfaces = vk_try_use_instance_extension("VK_EXT_metal_surface")
	} else when ODIN_OS == .Windows {
		vk_supports_win32_surfaces = vk_try_use_instance_extension("VK_KHR_win32_surface")
	} else {
		vk_supports_wayland_surfaces = vk_try_use_instance_extension("VK_KHR_wayland_surface")
		vk_supports_xlib_surfaces = vk_try_use_instance_extension("VK_KHR_xlib_surface")
	}
	ensure(
		vk_supports_metal_surfaces ||
		vk_supports_win32_surfaces ||
		vk_supports_wayland_surfaces ||
		vk_supports_xlib_surfaces,
		"The instance does not support presenting neither with Metal surfaces, Win32 surfaces, Wayland " +
		"surfaces nor XLib surfaces.",
	)

	if !has_debug_utils || !has_validation_layer {
		log.warn("The instance does not meet the requirements to enable validation.")
		vk_has_validation = false
	}

	log.debugf("Creating vulkan instance with extensions: %v.", vk_enabled_instance_extensions)

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
			apiVersion		= vk.MAKE_VERSION(1, 2, 0),
		},
	}
	if has_debug_utils {
		vk_link(&instance_desc, &vk_debug_messenger_descriptor)
	}

	vk_call(vk.CreateInstance(&instance_desc, nil, &vk_instance)) or_return
	vk.load_proc_addresses(vk_instance)

	if vk_has_validation {
		vk_call(vk.CreateDebugUtilsMessengerEXT(vk_instance, &vk_debug_messenger_descriptor, nil, &vk_debug_messenger)) or_return
	}

	version: u32
	vk.EnumerateInstanceVersion(&version)
	log.debugf("Using Vulkan 1.2.0 (available %d.%d.%d).", vk.VERSION_MAJOR(version), vk.VERSION_MINOR(version), vk.VERSION_PATCH(version))

	return nil
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

vk_init :: proc() -> Result {
	vk_load_instance_procs() or_return
	vk_prepare_debug_messenger()
	vk_init_instance() or_return

	return nil
}

vk_pre_fini :: proc() {
	vk.QueueWaitIdle(_queues[.Default].vk.queue)
	if _device_info.properties.transfer_queue {
		vk.QueueWaitIdle(_queues[.Transfer].vk.queue)
	}

	when ODIN_OS == .Darwin && ENABLE_TRACING {
		m3_end_tracing()
	}
}

vk_fini :: proc() {
	if _is_device_selected {
		vk.DestroyDescriptorSetLayout(vk_device, vk_descriptor_set_layout, nil)
		vk.DestroyDescriptorPool(vk_device, vk_descriptor_pool, nil)
		vk.DestroyPipelineLayout(vk_device, vk_compute_pipeline_layout, nil)
		vk.DestroyPipelineLayout(vk_device, vk_render_pipeline_layout, nil)
		vk.DestroyPipelineCache(vk_device, vk_pipeline_cache, nil)

		vk.DestroyDevice(vk_device, nil)
	}

	if vk_has_validation {
		vk.DestroyDebugUtilsMessengerEXT(vk_instance, vk_debug_messenger, nil)
	}
	vk.DestroyInstance(vk_instance, nil)

	dynlib.unload_library(vk_loader_lib)
}

vk_label_object_with_cstring :: proc(object: $T, type: vk.ObjectType, label: cstring) -> Result {
	if !vk_has_validation {
		return nil
	}

	label := vk.DebugUtilsObjectNameInfoEXT {
		sType		= .DEBUG_UTILS_OBJECT_NAME_INFO_EXT,
		objectType	= type,
		objectHandle	= cast(u64)cast(uintptr)object,
		pObjectName	= label,
	}
	vk_call(vk.SetDebugUtilsObjectNameEXT(vk_device, &label)) or_return

	return nil
}

vk_label_object_with_string :: proc(object: $T, type: vk.ObjectType, label: string) -> Result {
	if !vk_has_validation {
		return nil
	}

	label := vk.DebugUtilsObjectNameInfoEXT {
		sType		= .DEBUG_UTILS_OBJECT_NAME_INFO_EXT,
		objectType	= type,
		objectHandle	= cast(u64)object,
		pObjectName	= strings.clone_to_cstring(label, _temp_allocator),
	}
	vk_call(vk.SetDebugUtilsObjectNameEXT(vk_device, &label)) or_return

	return nil
}

vk_label_object :: proc {
	vk_label_object_with_string,
	vk_label_object_with_cstring,
}

vk_call :: proc(res: vk.Result, expr := #caller_expression, loc := #caller_location) -> Result {
	if res == .SUCCESS || res == .SUBOPTIMAL_KHR {
		return nil
	}
	
	log.errorf("Operation `%s` caused a vulkan error (%v).", expr, res, location=loc)
	return vk_result_to_gfx(res)
}

vk_link :: proc(a: ^$T, b: ^$U)
	where intrinsics.type_has_field(T, "pNext"),
		intrinsics.type_has_field(U, "pNext") {

	old_link := a.pNext
	a.pNext = b

	b.pNext = old_link
}

vk_result_to_gfx :: proc(res: vk.Result) -> Result {
	#partial switch res {
	case .SUCCESS:				return nil
	case .ERROR_OUT_OF_DEVICE_MEMORY:	return .Out_Of_Gpu_Memory
	case .ERROR_OUT_OF_HOST_MEMORY:		return .Out_Of_Gpu_Memory
	case:					return .Generic_Backend_Error
	}
}

@(init)
setup_vulkan_environment :: proc "contextless" () {
	when ODIN_OS != .Darwin {
		return
	}

	context = runtime.default_context()

	os.set_env("VK_LAYER_PATH", "./env/macOS/etc/vulkan/explicit_layer.d:./demo/env/macOS/etc/vulkan/explicit_layer.d")
	os.set_env("VK_DRIVER_FILES", "./env/macOS/etc/vulkan/icd.d:./demo/env/macOS/etc/vulkan/icd.d")
}

