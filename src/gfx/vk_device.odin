package gfx

import "base:runtime"
import "core:strings"
import "core:slice"
import "core:mem"
import "core:sync"
import vk "vendor:vulkan"

vk_Device_Info :: struct {
	physical_device:		vk.PhysicalDevice,

	properties:			vk.PhysicalDeviceProperties2,
	properties_11:			vk.PhysicalDeviceVulkan11Properties,
	properties_12:			vk.PhysicalDeviceVulkan12Properties,
	features:			vk.PhysicalDeviceFeatures2,
	features_11:			vk.PhysicalDeviceVulkan11Features,
	features_12:			vk.PhysicalDeviceVulkan12Features,
	synchronization2_features:	vk.PhysicalDeviceSynchronization2Features,
	dynamic_rendering_features:	vk.PhysicalDeviceDynamicRenderingFeaturesKHR,

	extensions:			[]vk.ExtensionProperties,

	memory_properties:		vk.PhysicalDeviceMemoryProperties2,
	private_memory:			u32,
	has_private_memory:		bool,
	shared_memory:			u32,
	has_shared_memory:		bool,
	updown_memory:			u32,
	has_updown_memory:		bool,

	queue_families:			[dynamic; 8]vk.QueueFamilyProperties2,
	default_queue_family:		u32,
	has_default_queue_family:	bool,
	transfer_queue_family:		u32,
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
vk_render_pipeline_layout:	vk.PipelineLayout

vk_descriptor_set_layout:	vk.DescriptorSetLayout
vk_descriptor_pool:		vk.DescriptorPool

vk_Descriptor_Binding :: enum u32 {
	Sampler					= 0,
	Texture_1d_Sampled_Image		= 1,
	Texture_2d_Sampled_Image		= 2,
	Texture_2d_Array_Sampled_Image		= 3,
	Texture_Cube_Sampled_Image		= 4,
	Texture_Cube_Array_Sampled_Image	= 5,
	Texture_3d_Sampled_Image		= 6,
	Texture_1d_Storage_Image		= 7,
	Texture_2d_Storage_Image		= 8,
	Texture_2d_Array_Storage_Image		= 9,
	Texture_3d_Storage_Image		= 10,
}

vk_enumerate_devices :: proc(allocator: runtime.Allocator) -> (devices: []Device_Info, res: Result) {
	device_count: u32
	vk_call(vk.EnumeratePhysicalDevices(vk_instance, &device_count, nil))
	available_devices := make([]vk.PhysicalDevice, device_count, _temp_allocator) or_return
	vk_call(vk.EnumeratePhysicalDevices(vk_instance, &device_count, raw_data(available_devices)))

	device_id: Device_Id

	vk_device_infos = make([dynamic]Device_Info, allocator) or_return
	for device in available_devices {
		info := vk_device_info_of(device) or_return

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
	device_info		:= &_available_devices[device]
	vk_device_info		= &device_info._platform.vk
	vk_physical_device	= vk_device_info.physical_device

	resize(&vk_enabled_device_extensions, 0)
	if vk_device_has_extension(device_info, "VK_KHR_portability_subset") {
		append(&vk_enabled_device_extensions, "VK_KHR_portability_subset")
	}
	append(&vk_enabled_device_extensions, "VK_KHR_dynamic_rendering")
	append(&vk_enabled_device_extensions, "VK_KHR_synchronization2")
	append(&vk_enabled_device_extensions, "VK_EXT_extended_dynamic_state")
	append(&vk_enabled_device_extensions, "VK_EXT_extended_dynamic_state2")
	append(&vk_enabled_device_extensions, "VK_KHR_swapchain")

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
		features		= {
			imageCubeArray				= true,
			samplerAnisotropy			= true,
			shaderSampledImageArrayDynamicIndexing	= true,
			shaderStorageImageArrayDynamicIndexing	= true,
			shaderStorageImageReadWithoutFormat	= true,
			shaderStorageImageWriteWithoutFormat	= true,
		},
	}
	device_features_11 := vk.PhysicalDeviceVulkan11Features {
		sType			= .PHYSICAL_DEVICE_VULKAN_1_1_FEATURES,
		pNext			= &device_features,
		shaderDrawParameters	= true,
	}
	device_features_12 := vk.PhysicalDeviceVulkan12Features {
		sType						= .PHYSICAL_DEVICE_VULKAN_1_2_FEATURES,
		pNext						= &device_features_11,
		timelineSemaphore				= true,
		bufferDeviceAddress				= true,
		runtimeDescriptorArray				= true,
		descriptorBindingPartiallyBound			= true,
		descriptorBindingStorageImageUpdateAfterBind	= true,
		descriptorBindingSampledImageUpdateAfterBind	= true,
		descriptorBindingUpdateUnusedWhilePending	= true,
		shaderStorageImageArrayNonUniformIndexing	= true,
		shaderSampledImageArrayNonUniformIndexing	= true,
	}
	dynamic_rendering_features := vk.PhysicalDeviceDynamicRenderingFeaturesKHR {
		sType			= .PHYSICAL_DEVICE_DYNAMIC_RENDERING_FEATURES_KHR,
		pNext			= &device_features_12,
		dynamicRendering	= true,
	}
	synchronization2_features := vk.PhysicalDeviceSynchronization2FeaturesKHR {
		sType			= .PHYSICAL_DEVICE_SYNCHRONIZATION_2_FEATURES_KHR,
		pNext			= &dynamic_rendering_features,
		synchronization2	= true,
	}
	extended_dynamic_state_features := vk.PhysicalDeviceExtendedDynamicStateFeaturesEXT {
		sType			= .PHYSICAL_DEVICE_EXTENDED_DYNAMIC_STATE_FEATURES_EXT,
		pNext			= &synchronization2_features,
		extendedDynamicState	= true,
	}
	extended_dynamic_state_2_features := vk.PhysicalDeviceExtendedDynamicState2FeaturesEXT {
		sType			= .PHYSICAL_DEVICE_EXTENDED_DYNAMIC_STATE_2_FEATURES_EXT,
		pNext			= &extended_dynamic_state_features,
		extendedDynamicState2	= true,
	}
	descriptor := vk.DeviceCreateInfo {
		sType			= .DEVICE_CREATE_INFO,
		pNext			= &extended_dynamic_state_2_features,
		queueCreateInfoCount	= cast(u32)len(queue_descriptors),
		pQueueCreateInfos	= raw_data(queue_descriptors),
		enabledExtensionCount	= cast(u32)len(vk_enabled_device_extensions),
		ppEnabledExtensionNames	= raw_data(vk_enabled_device_extensions[:]),
	}

	// log.debugf("Creating device with extensions: %v.", vk_enabled_device_extensions)
	vk_call(vk.CreateDevice(vk_physical_device, &descriptor, nil, &vk_device)) or_return

	vk_setup_descriptor_pool() or_return
	vk_setup_pipeline_layouts() or_return
	vk_setup_pipeline_cache() or_return

	return nil
}

vk_setup_pipeline_layouts :: proc() -> Result {
	compute_push_constant_range := vk.PushConstantRange {
		stageFlags	= { .COMPUTE },
		offset		= 0,
		size		= size_of(uintptr) * 8,
	}
	compute_layout_info := vk.PipelineLayoutCreateInfo {
		sType			= .PIPELINE_LAYOUT_CREATE_INFO,
		pushConstantRangeCount	= 1,
		pPushConstantRanges	= &compute_push_constant_range,
		setLayoutCount		= 1,
		pSetLayouts		= &vk_descriptor_set_layout,
	}

	render_push_constant_range := vk.PushConstantRange {
		stageFlags	= { .VERTEX, .FRAGMENT },
		offset		= 0,
		size		= size_of(uintptr) * 8,
	}
	render_layout_info := vk.PipelineLayoutCreateInfo {
		sType			= .PIPELINE_LAYOUT_CREATE_INFO,
		pushConstantRangeCount	= 1,
		pPushConstantRanges	= &render_push_constant_range,
		setLayoutCount		= 1,
		pSetLayouts		= &vk_descriptor_set_layout,
	}

	vk_call(vk.CreatePipelineLayout(vk_device, &compute_layout_info, nil, &vk_compute_pipeline_layout)) or_return
	vk_call(vk.CreatePipelineLayout(vk_device, &render_layout_info, nil, &vk_render_pipeline_layout)) or_return

	return nil
}

vk_setup_pipeline_cache :: proc() -> Result {
	// TODO: Persistent pipeline cache
	pipeline_cache_info := vk.PipelineCacheCreateInfo {
		sType			= .PIPELINE_CACHE_CREATE_INFO,
		initialDataSize		= 0,
	}
	vk_call(vk.CreatePipelineCache(vk_device, &pipeline_cache_info, nil, &vk_pipeline_cache)) or_return

	return nil
}

vk_setup_descriptor_pool :: proc() -> Result {
	MAX_DESCRIPTOR_SETS	:: 64
	MAX_TEXTURES_PER_SET	:: 8192
	MAX_SAMPLERS_PER_SET	:: 64

	descriptor_pools := []vk.DescriptorPoolSize {
		{ .SAMPLED_IMAGE,	MAX_DESCRIPTOR_SETS * MAX_TEXTURES_PER_SET },
		{ .STORAGE_IMAGE,	MAX_DESCRIPTOR_SETS * MAX_TEXTURES_PER_SET },
		{ .SAMPLER,		MAX_DESCRIPTOR_SETS * MAX_SAMPLERS_PER_SET },
	}
	descriptor_pool_info := vk.DescriptorPoolCreateInfo {
		sType			= .DESCRIPTOR_POOL_CREATE_INFO,
		flags			= { .FREE_DESCRIPTOR_SET, .UPDATE_AFTER_BIND },
		maxSets			= 256,
		poolSizeCount		= cast(u32)len(descriptor_pools),
		pPoolSizes		= raw_data(descriptor_pools),
	}
	vk_call(vk.CreateDescriptorPool(vk_device, &descriptor_pool_info, nil, &vk_descriptor_pool)) or_return

	descriptor_set_bindings := [vk_Descriptor_Binding]vk.DescriptorSetLayoutBinding {
		.Sampler = {
			binding			= cast(u32)vk_Descriptor_Binding.Sampler,
			descriptorType		= .SAMPLER,
			descriptorCount		= MAX_SAMPLERS_PER_SET,
			stageFlags		= { .VERTEX, .FRAGMENT, .COMPUTE },
		},
		.Texture_1d_Sampled_Image = {
			binding			= cast(u32)vk_Descriptor_Binding.Texture_1d_Sampled_Image,
			descriptorType		= .SAMPLED_IMAGE,
			descriptorCount		= MAX_TEXTURES_PER_SET,
			stageFlags		= { .VERTEX, .FRAGMENT, .COMPUTE },
		},
		.Texture_2d_Sampled_Image = {
			binding			= cast(u32)vk_Descriptor_Binding.Texture_2d_Sampled_Image,
			descriptorType		= .SAMPLED_IMAGE,
			descriptorCount		= MAX_TEXTURES_PER_SET,
			stageFlags		= { .VERTEX, .FRAGMENT, .COMPUTE },
		},
		.Texture_2d_Array_Sampled_Image = {
			binding			= cast(u32)vk_Descriptor_Binding.Texture_2d_Array_Sampled_Image,
			descriptorType		= .SAMPLED_IMAGE,
			descriptorCount		= MAX_TEXTURES_PER_SET,
			stageFlags		= { .VERTEX, .FRAGMENT, .COMPUTE },
		},
		.Texture_Cube_Sampled_Image = {
			binding			= cast(u32)vk_Descriptor_Binding.Texture_Cube_Sampled_Image,
			descriptorType		= .SAMPLED_IMAGE,
			descriptorCount		= MAX_TEXTURES_PER_SET,
			stageFlags		= { .VERTEX, .FRAGMENT, .COMPUTE },
		},
		.Texture_Cube_Array_Sampled_Image = {
			binding			= cast(u32)vk_Descriptor_Binding.Texture_Cube_Array_Sampled_Image,
			descriptorType		= .SAMPLED_IMAGE,
			descriptorCount		= MAX_TEXTURES_PER_SET,
			stageFlags		= { .VERTEX, .FRAGMENT, .COMPUTE },
		},
		.Texture_3d_Sampled_Image = {
			binding			= cast(u32)vk_Descriptor_Binding.Texture_3d_Sampled_Image,
			descriptorType		= .SAMPLED_IMAGE,
			descriptorCount		= MAX_TEXTURES_PER_SET,
			stageFlags		= { .VERTEX, .FRAGMENT, .COMPUTE },
		},
		.Texture_1d_Storage_Image = {
			binding			= cast(u32)vk_Descriptor_Binding.Texture_1d_Storage_Image,
			descriptorType		= .STORAGE_IMAGE,
			descriptorCount		= MAX_TEXTURES_PER_SET,
			stageFlags		= { .VERTEX, .FRAGMENT, .COMPUTE },
		},
		.Texture_2d_Storage_Image = {
			binding			= cast(u32)vk_Descriptor_Binding.Texture_2d_Storage_Image,
			descriptorType		= .STORAGE_IMAGE,
			descriptorCount		= MAX_TEXTURES_PER_SET,
			stageFlags		= { .VERTEX, .FRAGMENT, .COMPUTE },
		},
		.Texture_2d_Array_Storage_Image = {
			binding			= cast(u32)vk_Descriptor_Binding.Texture_2d_Array_Storage_Image,
			descriptorType		= .STORAGE_IMAGE,
			descriptorCount		= MAX_TEXTURES_PER_SET,
			stageFlags		= { .VERTEX, .FRAGMENT, .COMPUTE },
		},
		.Texture_3d_Storage_Image = {
			binding			= cast(u32)vk_Descriptor_Binding.Texture_3d_Storage_Image,
			descriptorType		= .STORAGE_IMAGE,
			descriptorCount		= MAX_TEXTURES_PER_SET,
			stageFlags		= { .VERTEX, .FRAGMENT, .COMPUTE },
		},
	}
	binding_flags := [vk_Descriptor_Binding]vk.DescriptorBindingFlags {
		.Sampler			= { .PARTIALLY_BOUND, .UPDATE_AFTER_BIND },
		.Texture_1d_Sampled_Image	= { .PARTIALLY_BOUND, .UPDATE_AFTER_BIND },
		.Texture_1d_Storage_Image	= { .PARTIALLY_BOUND, .UPDATE_AFTER_BIND },
		.Texture_2d_Sampled_Image	= { .PARTIALLY_BOUND, .UPDATE_AFTER_BIND },
		.Texture_2d_Storage_Image	= { .PARTIALLY_BOUND, .UPDATE_AFTER_BIND },
		.Texture_2d_Array_Sampled_Image	= { .PARTIALLY_BOUND, .UPDATE_AFTER_BIND },
		.Texture_2d_Array_Storage_Image = { .PARTIALLY_BOUND, .UPDATE_AFTER_BIND },
		.Texture_Cube_Sampled_Image	= { .PARTIALLY_BOUND, .UPDATE_AFTER_BIND },
		.Texture_Cube_Array_Sampled_Image = { .PARTIALLY_BOUND, .UPDATE_AFTER_BIND },
		.Texture_3d_Sampled_Image	= { .PARTIALLY_BOUND, .UPDATE_AFTER_BIND },
		.Texture_3d_Storage_Image	= { .PARTIALLY_BOUND, .UPDATE_AFTER_BIND },
	}
	descriptor_set_flags_info := vk.DescriptorSetLayoutBindingFlagsCreateInfo {
		sType		= .DESCRIPTOR_SET_LAYOUT_BINDING_FLAGS_CREATE_INFO,
		bindingCount	= cast(u32)len(binding_flags),
		pBindingFlags	= raw_data(slice.enumerated_array(&binding_flags)),
	}
	descriptor_set_layout_info := vk.DescriptorSetLayoutCreateInfo {
		sType			= .DESCRIPTOR_SET_LAYOUT_CREATE_INFO,
		flags			= { .UPDATE_AFTER_BIND_POOL },
		pNext			= &descriptor_set_flags_info,
		bindingCount		= cast(u32)len(descriptor_set_bindings),
		pBindings		= raw_data(slice.enumerated_array(&descriptor_set_bindings)),
	}
	vk_call(
		vk.CreateDescriptorSetLayout(vk_device, &descriptor_set_layout_info, nil, &vk_descriptor_set_layout),
	) or_return

	return nil
}

vk_device_info_of :: proc(device: vk.PhysicalDevice) -> (info: Device_Info, res: Result) {
	vk_info := &info._platform.vk

	extension_count: u32
	vk_call(vk.EnumerateDeviceExtensionProperties(device, nil, &extension_count, nil)) or_return
	vk_info.extensions = make([]vk.ExtensionProperties, extension_count, _global_allocator)
	vk_call(vk.EnumerateDeviceExtensionProperties(device, nil, &extension_count, raw_data(vk_info.extensions))) or_return

	vk_info.physical_device		= device

	vk_info.properties.sType	= .PHYSICAL_DEVICE_PROPERTIES_2
	vk_info.properties.pNext	= &vk_info.properties_11
	vk_info.properties_11.sType	= .PHYSICAL_DEVICE_VULKAN_1_1_PROPERTIES
	vk_info.properties_11.pNext	= &vk_info.properties_12
	vk_info.properties_12.sType	= .PHYSICAL_DEVICE_VULKAN_1_2_PROPERTIES
	vk.GetPhysicalDeviceProperties2(device, &vk_info.properties)

	vk_info.features.sType		= .PHYSICAL_DEVICE_FEATURES_2
	vk_info.features.pNext		= &vk_info.features_11
	vk_info.features_11.sType	= .PHYSICAL_DEVICE_VULKAN_1_1_FEATURES
	vk_info.features_11.pNext	= &vk_info.features_12
	vk_info.features_12.sType	= .PHYSICAL_DEVICE_VULKAN_1_2_FEATURES
	vk_info.features_12.pNext	= &vk_info.dynamic_rendering_features
	vk_info.dynamic_rendering_features.sType	= .PHYSICAL_DEVICE_DYNAMIC_RENDERING_FEATURES_KHR
	vk_info.dynamic_rendering_features.pNext	= &vk_info.synchronization2_features
	vk_info.synchronization2_features.sType		= .PHYSICAL_DEVICE_SYNCHRONIZATION_2_FEATURES
	vk.GetPhysicalDeviceFeatures2(device, &vk_info.features)

	vk_find_memory_types(device, &info)
	vk_find_queue_families(device, &info)

	info.name = strings.clone_from_cstring_bounded(
		cast(cstring)&vk_info.properties.properties.deviceName[0],
		len(vk_info.properties.properties.deviceName),
		_global_allocator,
	)
	info.driver = strings.clone_from_cstring_bounded(
		cast(cstring)&vk_info.properties_12.driverName[0],
		len(vk_info.properties_12.driverName),
		_global_allocator,
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

	vk_info.shared_memory, vk_info.has_shared_memory =
		vk_search_for_memory_type(info, { .DEVICE_LOCAL, .HOST_VISIBLE, .HOST_COHERENT })
	if !vk_info.has_shared_memory {
		vk_info.shared_memory, vk_info.has_shared_memory =
			vk_search_for_memory_type(info, { .HOST_VISIBLE, .HOST_COHERENT })
	} else {
		info.properties.host_accessible_device_memory = true
	}

	vk_info.updown_memory, vk_info.has_updown_memory =
		vk_search_for_memory_type(info, { .DEVICE_LOCAL, .HOST_VISIBLE, .HOST_COHERENT })
	updown_memory_size := vk_info.memory_properties.memoryProperties.memoryHeaps[
		vk_info.memory_properties.memoryProperties.memoryTypes[vk_info.updown_memory].heapIndex].size
	if !vk_info.has_updown_memory || updown_memory_size < 512 * mem.Megabyte {
		vk_info.updown_memory, vk_info.has_updown_memory =
			vk_search_for_memory_type(info, { .HOST_VISIBLE, .HOST_COHERENT })
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
	// if !vk_info.has_transfer_queue_family {
	// 	if vk_info.queue_families[vk_info.default_queue_family].queueFamilyProperties.queueCount > 1 {
	// 		vk_info.transfer_queue_family = vk_info.default_queue_family
	// 	}
	// }
}

vk_is_device_suitable :: proc(device: vk.PhysicalDevice, info: ^Device_Info) -> bool {
	vk_info := &info._platform.vk

	return vk_device_has_extension(info, "VK_KHR_dynamic_rendering") &&
		vk_device_has_extension(info, "VK_KHR_synchronization2") &&
		vk_device_has_extension(info, "VK_EXT_extended_dynamic_state") &&
		vk_device_has_extension(info, "VK_EXT_extended_dynamic_state2") &&
		vk_device_has_extension(info, "VK_KHR_swapchain") &&
		vk_info.features.features.imageCubeArray == true &&
		vk_info.features.features.samplerAnisotropy == true &&
		vk_info.features.features.shaderSampledImageArrayDynamicIndexing == true &&
		vk_info.features.features.shaderStorageImageArrayDynamicIndexing == true &&
		vk_info.features.features.shaderStorageImageReadWithoutFormat == true &&
		vk_info.features.features.shaderStorageImageWriteWithoutFormat == true &&
		vk_info.features_11.shaderDrawParameters == true &&
		vk_info.features_12.timelineSemaphore == true &&
		vk_info.features_12.bufferDeviceAddress == true &&
		vk_info.features_12.runtimeDescriptorArray == true &&
		vk_info.features_12.descriptorBindingPartiallyBound == true &&
		vk_info.features_12.descriptorBindingStorageImageUpdateAfterBind == true &&
		vk_info.features_12.descriptorBindingSampledImageUpdateAfterBind == true &&
		vk_info.features_12.descriptorBindingUpdateUnusedWhilePending == true &&
		vk_info.features_12.shaderSampledImageArrayNonUniformIndexing == true &&
		vk_info.features_12.shaderStorageImageArrayNonUniformIndexing == true &&
		vk_info.synchronization2_features.synchronization2 == true &&
		vk_info.dynamic_rendering_features.dynamicRendering == true &&
		vk_info.has_default_queue_family &&
		vk_info.has_private_memory &&
		vk_info.has_updown_memory &&
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

