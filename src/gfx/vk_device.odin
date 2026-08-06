package gfx

import "base:runtime"
import "core:strings"
import "core:mem"
import "core:sync"
import vk "vendor:vulkan"

vk_Device_Info :: struct {
	physical_device:	vk.PhysicalDevice,

	properties:		vk.PhysicalDeviceProperties2,
	features:		vk.PhysicalDeviceFeatures2,
	device_address_features:	vk.PhysicalDeviceBufferDeviceAddressFeatures,

	extensions:		[]vk.ExtensionProperties,

	memory_properties:	vk.PhysicalDeviceMemoryProperties2,
	private_memory:		u32,
	has_private_memory:	bool,
	shared_memory:		u32,
	has_shared_memory:	bool,

	queue_families:		[dynamic; 8]vk.QueueFamilyProperties2,
	default_queue_family:	u32,
	has_default_queue_family:	bool,
	transfer_queue_family:	u32,
	has_transfer_queue_family:	bool,
}

vk_device_infos:		[dynamic]Device_Info
vk_device_info:			^vk_Device_Info
vk_physical_device:		vk.PhysicalDevice

vk_device:			vk.Device
vk_enabled_device_extensions:	[dynamic; 8]cstring

vk_pipeline_cache:		vk.PipelineCache
vk_pipeline_cache_mutex:	sync.Mutex
vk_compute_pipeline_layout:	vk.PipelineLayout

vk_enumerate_devices :: proc(allocator: runtime.Allocator) -> (devices: []Device_Info, res: Result) {
	device_count: u32
	vk_call(vk.EnumeratePhysicalDevices(vk_instance, &device_count, nil))
	available_devices := make([]vk.PhysicalDevice, device_count, _temp_allocator) or_return
	vk_call(vk.EnumeratePhysicalDevices(vk_instance, &device_count, raw_data(available_devices)))

	device_id: Device_Id

	vk_device_infos = make([dynamic]Device_Info, allocator) or_return
	for device in available_devices {
		info := vk_device_info_of(device)

		if !vk_is_device_suitable(device, &info) {
			continue
		}

		info.id	= device_id
		append(&vk_device_infos, info)

		device_id += 1
	}

	return vk_device_infos[:], nil
}

vk_select_device :: proc(device: Device_Id) -> Result {
	vk_device_info		= &vk_device_infos[device]._platform.vk
	vk_physical_device	= vk_device_info.physical_device

	resize(&vk_enabled_device_extensions, 0)

	when ODIN_OS == .Darwin {
		append(&vk_enabled_device_extensions, "VK_KHR_portability_subset")
		append(&vk_enabled_device_extensions, "VK_EXT_metal_objects")
	}

	queue_descriptors: []vk.DeviceQueueCreateInfo

	default_queue_priority: f32 = 0.9
	default_queue_descriptor := vk.DeviceQueueCreateInfo {
		sType			= .DEVICE_QUEUE_CREATE_INFO,
		queueFamilyIndex	= vk_device_info.default_queue_family,
		queueCount		= 1,
		pQueuePriorities	= &default_queue_priority,
	}

	if vk_device_info.has_transfer_queue_family {
		transfer_queue_priority: f32 = 1.0
		transfer_queue_descriptor := vk.DeviceQueueCreateInfo {
			sType			= .DEVICE_QUEUE_CREATE_INFO,
			queueFamilyIndex	= vk_device_info.transfer_queue_family,
			queueCount		= 1,
			pQueuePriorities	= &transfer_queue_priority,
		}

		queue_descriptors = { default_queue_descriptor, transfer_queue_descriptor }
	} else {
		queue_descriptors = { default_queue_descriptor }
	}

	device_features := vk.PhysicalDeviceFeatures2 {
		sType			= .PHYSICAL_DEVICE_FEATURES_2,
		pNext			= &vk_debug_messenger_descriptor if vk_has_validation else nil,
		features		= {
			imageCubeArray		= true,
			samplerAnisotropy	= true,
		},
	}
	buffer_features := vk.PhysicalDeviceBufferDeviceAddressFeatures {
		sType			= .PHYSICAL_DEVICE_BUFFER_DEVICE_ADDRESS_FEATURES,
		pNext			= &device_features,
		bufferDeviceAddress	= true,
	}
	descriptor := vk.DeviceCreateInfo {
		sType			= .DEVICE_CREATE_INFO,
		pNext			= &buffer_features,
		queueCreateInfoCount	= cast(u32)len(queue_descriptors),
		pQueueCreateInfos	= raw_data(queue_descriptors),
		enabledExtensionCount	= cast(u32)len(vk_enabled_device_extensions),
		ppEnabledExtensionNames	= raw_data(vk_enabled_device_extensions[:]),
	}

	// log.debugf("Creating device with extensions: %v.", vk_enabled_device_extensions)
	vk_call(vk.CreateDevice(vk_physical_device, &descriptor, nil, &vk_device))

	vk_setup_pipeline_layouts()

	return nil
}

vk_setup_pipeline_layouts :: proc() {
	compute_push_constant_range := vk.PushConstantRange {
		stageFlags	= { .COMPUTE },
		offset		= 0,
		size		= size_of(uintptr) * 8,
	}
	compute_layout_info := vk.PipelineLayoutCreateInfo {
		sType			= .PIPELINE_LAYOUT_CREATE_INFO,
		setLayoutCount		= 0,
		pushConstantRangeCount	= 1,
		pPushConstantRanges	= &compute_push_constant_range,
	}

	vk_call(vk.CreatePipelineLayout(vk_device, &compute_layout_info, nil, &vk_compute_pipeline_layout))
}

vk_setup_pipeline_cache :: proc() {
	// TODO: Persistent pipeline cache
	pipeline_cache_info := vk.PipelineCacheCreateInfo {
		sType			= .PIPELINE_CACHE_CREATE_INFO,
		initialDataSize		= 0,
	}
	vk_call(vk.CreatePipelineCache(vk_device, &pipeline_cache_info, nil, &vk_pipeline_cache))
}

vk_device_info_of :: proc(device: vk.PhysicalDevice) -> (info: Device_Info) {
	vk_info := &info._platform.vk

	extension_count: u32
	vk_call(vk.EnumerateDeviceExtensionProperties(device, nil, &extension_count, nil))
	vk_info.extensions = make([]vk.ExtensionProperties, extension_count, _global_allocator)
	vk_call(vk.EnumerateDeviceExtensionProperties(device, nil, &extension_count, raw_data(vk_info.extensions)))

	vk_info.physical_device		= device
	vk_info.properties.sType	= .PHYSICAL_DEVICE_PROPERTIES_2
	vk.GetPhysicalDeviceProperties2(device, &vk_info.properties)

	vk_info.features.sType = .PHYSICAL_DEVICE_FEATURES_2
	vk_info.device_address_features.sType = .PHYSICAL_DEVICE_BUFFER_DEVICE_ADDRESS_FEATURES
	vk_link(&vk_info.features, &vk_info.device_address_features)
	vk.GetPhysicalDeviceFeatures2(device, &vk_info.features)

	vk_find_memory_types(device, &info)
	vk_find_queue_families(device, &info)

	// TODO: Fix memory leak
	info.name = strings.string_from_ptr(
		raw_data(vk_info.properties.properties.deviceName[:]),
		len(vk_info.properties.properties.deviceName),
	)
	info.type = vk_PHYSICAL_DEVICE_TYPE_TO_GFX[vk_info.properties.properties.deviceType]

	info.limits.allocation_alignment	= 16 * mem.Kilobyte
	info.limits.min_allocation_size		= 16 * mem.Kilobyte
	info.properties.transfer_queue		= vk_info.has_transfer_queue_family

	return
}

vk_device_has_extension :: proc(info: ^Device_Info, extension: string) -> bool {
	vk_info := &info._platform.vk

	for &property in vk_info.extensions {
		if strings.string_from_null_terminated_ptr(
			raw_data(property.extensionName[:]),
			len(property.extensionName),
		) == extension {
			
			return true
		}
	}

	return false
}

vk_find_memory_types :: proc(device: vk.PhysicalDevice, info: ^Device_Info) {
	vk_info := &info._platform.vk
	
	vk_info.memory_properties.sType = .PHYSICAL_DEVICE_MEMORY_PROPERTIES_2
	vk.GetPhysicalDeviceMemoryProperties2(device, &vk_info.memory_properties)

	vk_info.private_memory, vk_info.has_private_memory = vk_search_for_memory_type(info, { .DEVICE_LOCAL })

	vk_info.shared_memory, vk_info.has_shared_memory = vk_search_for_memory_type(info, { .DEVICE_LOCAL, .HOST_VISIBLE })
	if !vk_info.has_shared_memory {
		vk_info.shared_memory, vk_info.has_shared_memory = vk_search_for_memory_type(info, { .HOST_VISIBLE })
	} else {
		info.properties.host_accessible_device_memory = true
	}

	if vk_info.has_shared_memory {
		info.properties.coherent_memory =
			.HOST_COHERENT in vk_info.memory_properties.memoryProperties.memoryTypes[vk_info.shared_memory].propertyFlags ||
			.HOST_CACHED in vk_info.memory_properties.memoryProperties.memoryTypes[vk_info.shared_memory].propertyFlags
	}
}

vk_search_for_memory_type :: proc(info: ^Device_Info, properties: vk.MemoryPropertyFlags) -> (type_idx: u32, found: bool) {
	vk_info := &info._platform.vk
	memory_properties := &vk_info.memory_properties.memoryProperties

	outer: for i in 0..<memory_properties.memoryTypeCount {
		memory_type := &memory_properties.memoryTypes[i]

		if properties == memory_type.propertyFlags {
			return i, true
		}

		for property in properties {
			if property not_in memory_type.propertyFlags {
				continue outer
			}
		}

		type_idx	= i
		found		= true
	}

	return
}

vk_find_queue_families :: proc(device: vk.PhysicalDevice, info: ^Device_Info) {
	vk_info := &info._platform.vk

	queue_family_count: u32
	vk.GetPhysicalDeviceQueueFamilyProperties2(device, &queue_family_count, nil)

	resize(&vk_info.queue_families, queue_family_count)
	for &family in vk_info.queue_families {
		family.sType = .QUEUE_FAMILY_PROPERTIES_2
	}
	vk.GetPhysicalDeviceQueueFamilyProperties2(device, &queue_family_count, raw_data(vk_info.queue_families[:]))

	vk_info.has_default_queue_family = false
	for queue, i in vk_info.queue_families {
		if .TRANSFER not_in queue.queueFamilyProperties.queueFlags ||
			.COMPUTE not_in queue.queueFamilyProperties.queueFlags ||
			.GRAPHICS not_in queue.queueFamilyProperties.queueFlags {

			continue
		}

		vk_info.default_queue_family = cast(u32)i
		vk_info.has_default_queue_family = true
		break
	}

	if !vk_info.has_default_queue_family {
		return
	}

	for queue, i in vk_info.queue_families {
		if .TRANSFER not_in queue.queueFamilyProperties.queueFlags ||
			cast(u32)i == vk_info.default_queue_family {
			
			continue
		}

		if .COMPUTE not_in queue.queueFamilyProperties.queueFlags &&
			.GRAPHICS not_in queue.queueFamilyProperties.queueFlags {
			
			vk_info.transfer_queue_family = cast(u32)i
			vk_info.has_transfer_queue_family = true
			break
		}

		if !vk_info.has_transfer_queue_family {
			vk_info.transfer_queue_family = cast(u32)i
			vk_info.has_transfer_queue_family = true
		}
	}

	// NOTE: If we couln't find a different queue family for transfer, then let's try to use the default one as
	//	transfer.
	if !vk_info.has_transfer_queue_family {
		if vk_info.queue_families[vk_info.default_queue_family].queueFamilyProperties.queueCount > 1 {
			vk_info.transfer_queue_family = vk_info.default_queue_family
		}
	}
}

vk_is_device_suitable :: proc(device: vk.PhysicalDevice, info: ^Device_Info) -> bool {
	vk_info := &info._platform.vk

	when ODIN_OS == .Darwin {
		ensure(
			vk_device_has_extension(info, "VK_KHR_portability_subset"),
			"Vulkan on macOS does not have the VK_KHR_portability_subset device extension. Broken install?",
		)
		ensure(
			vk_device_has_extension(info, "VK_EXT_metal_objects"),
			"Vulkan on macOS does not have the VK_EXT_metal_objects device extension. Broken install?",
		)
	}

	return vk_info.device_address_features.bufferDeviceAddress == true &&
		vk_info.has_default_queue_family &&
		vk_info.has_private_memory &&
		vk_info.has_shared_memory
}

@(rodata)
vk_PHYSICAL_DEVICE_TYPE_TO_GFX := [vk.PhysicalDeviceType]Device_Type {
	.OTHER		= .Other,
	.INTEGRATED_GPU	= .Integrated,
	.DISCRETE_GPU	= .Discrete,
	.VIRTUAL_GPU	= .Other,
	.CPU		= .Other,
}

