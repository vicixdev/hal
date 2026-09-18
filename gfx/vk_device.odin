package vicixdev_gfx

/*
This Source Code Form is subject to the terms of the Mozilla Public
License, v. 2.0. If a copy of the MPL was not distributed with this
file, You can obtain one at https://mozilla.org/MPL/2.0/.
*/



import "base:runtime"
import "core:strings"
import "core:slice"
import "core:mem"
import "core:sync"
import vk "vendor:vulkan"

_vk_Device_Info :: struct {
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

_vk_device_infos:		[dynamic]Device_Info
_vk_device_info:			^_vk_Device_Info
_vk_physical_device:		vk.PhysicalDevice

_vk_device:			vk.Device
_vk_enabled_device_extensions:	[dynamic; 8]cstring

_vk_pipeline_cache:		vk.PipelineCache
_vk_pipeline_cache_mutex:	sync.Mutex
_vk_compute_pipeline_layout:	vk.PipelineLayout
_vk_render_pipeline_layout:	vk.PipelineLayout

_vk_descriptor_set_layout:	vk.DescriptorSetLayout
_vk_descriptor_pool:		vk.DescriptorPool

_vk_Descriptor_Binding :: enum u32 {
	Sampler					= 0,
	Texture_1d_Sampled_Image		= 1,
	Texture_2d_Sampled_Image		= 2,
	Texture_2d_Array_Sampled_Image		= 3,
	Texture_Cube_Sampled_Image		= 4,
	Texture_Cube_Array_Sampled_Image	= 5,
	Texture_3d_Sampled_Image		= 6,
	Texture_2d_Multisampled_Image		= 7,
	Texture_2d_Array_Multisampled_Image	= 8,
	Texture_1d_Storage_Image		= 9,
	Texture_2d_Storage_Image		= 10,
	Texture_2d_Array_Storage_Image		= 11,
	Texture_3d_Storage_Image		= 12,
}

_vk_enumerate_devices :: proc(allocator: runtime.Allocator) -> (devices: []Device_Info, res: Result) {
	device_count: u32
	_vk_call(vk.EnumeratePhysicalDevices(_vk_instance, &device_count, nil))
	available_devices := make([]vk.PhysicalDevice, device_count, _temp_allocator) or_return
	_vk_call(vk.EnumeratePhysicalDevices(_vk_instance, &device_count, raw_data(available_devices)))

	device_id: Device_Id

	_vk_device_infos = make([dynamic]Device_Info, allocator) or_return
	for device in available_devices {
		info := _vk_device_info_of(device) or_return

		if !_vk_is_device_suitable(device, &info) {
			continue
		}

		info.id	= device_id
		append(&_vk_device_infos, info)

		device_id += 1
	}

	return _vk_device_infos[:], nil
}

_vk_select_device :: proc(device: Device_Id) -> Result {
	device_info		:= &_available_devices[device]
	_vk_device_info		= &device_info._platform.vk
	_vk_physical_device	= _vk_device_info.physical_device

	resize(&_vk_enabled_device_extensions, 0)
	if _vk_device_has_extension(device_info, "VK_KHR_portability_subset") {
		append(&_vk_enabled_device_extensions, "VK_KHR_portability_subset")
	}
	append(&_vk_enabled_device_extensions, "VK_KHR_dynamic_rendering")
	append(&_vk_enabled_device_extensions, "VK_KHR_synchronization2")
	append(&_vk_enabled_device_extensions, "VK_EXT_extended_dynamic_state")
	append(&_vk_enabled_device_extensions, "VK_EXT_extended_dynamic_state2")
	append(&_vk_enabled_device_extensions, "VK_KHR_swapchain")

	has_unified_image_layouts := false
	// has_unified_image_layouts := _vk_device_has_extension(device_info, "VK_KHR_unified_image_layouts")
	// if has_unified_image_layouts {
	// 	append(&_vk_enabled_device_extensions, "VK_KHR_unified_image_layouts")
	// }

	queue_descriptors: []vk.DeviceQueueCreateInfo

	default_queue_priority: f32 = 0.9
	default_queue_descriptor := vk.DeviceQueueCreateInfo {
		sType			= .DEVICE_QUEUE_CREATE_INFO,
		queueFamilyIndex	= _vk_device_info.default_queue_family,
		queueCount		= 1,
		pQueuePriorities	= &default_queue_priority,
	}

	if _vk_device_info.has_transfer_queue_family {
		transfer_queue_priority: f32 = 1.0
		transfer_queue_descriptor := vk.DeviceQueueCreateInfo {
			sType			= .DEVICE_QUEUE_CREATE_INFO,
			queueFamilyIndex	= _vk_device_info.transfer_queue_family,
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
			shaderInt16				= true,
		},
	}
	device_features_11 := vk.PhysicalDeviceVulkan11Features {
		sType			= .PHYSICAL_DEVICE_VULKAN_1_1_FEATURES,
		shaderDrawParameters	= true,
	}
	_vk_link(&device_features, &device_features_11)
	device_features_12 := vk.PhysicalDeviceVulkan12Features {
		sType						= .PHYSICAL_DEVICE_VULKAN_1_2_FEATURES,
		timelineSemaphore				= true,
		bufferDeviceAddress				= true,
		runtimeDescriptorArray				= true,
		descriptorBindingPartiallyBound			= true,
		descriptorBindingStorageImageUpdateAfterBind	= true,
		descriptorBindingSampledImageUpdateAfterBind	= true,
		descriptorBindingUpdateUnusedWhilePending	= true,
		shaderStorageImageArrayNonUniformIndexing	= true,
		shaderSampledImageArrayNonUniformIndexing	= true,
		shaderInt8					= true,
	}
	_vk_link(&device_features_11, &device_features_12)
	dynamic_rendering_features := vk.PhysicalDeviceDynamicRenderingFeaturesKHR {
		sType			= .PHYSICAL_DEVICE_DYNAMIC_RENDERING_FEATURES_KHR,
		dynamicRendering	= true,
	}
	_vk_link(&device_features_12, &dynamic_rendering_features)
	synchronization2_features := vk.PhysicalDeviceSynchronization2FeaturesKHR {
		sType			= .PHYSICAL_DEVICE_SYNCHRONIZATION_2_FEATURES_KHR,
		synchronization2	= true,
	}
	_vk_link(&dynamic_rendering_features, &synchronization2_features)
	extended_dynamic_state_features := vk.PhysicalDeviceExtendedDynamicStateFeaturesEXT {
		sType			= .PHYSICAL_DEVICE_EXTENDED_DYNAMIC_STATE_FEATURES_EXT,
		extendedDynamicState	= true,
	}
	_vk_link(&synchronization2_features, &extended_dynamic_state_features)
	extended_dynamic_state_2_features := vk.PhysicalDeviceExtendedDynamicState2FeaturesEXT {
		sType			= .PHYSICAL_DEVICE_EXTENDED_DYNAMIC_STATE_2_FEATURES_EXT,
		extendedDynamicState2	= true,
	}
	_vk_link(&extended_dynamic_state_features, &extended_dynamic_state_2_features)
	if has_unified_image_layouts {
		unified_image_layouts_features := vk.PhysicalDeviceUnifiedImageLayoutsFeaturesKHR {
			sType			= .PHYSICAL_DEVICE_UNIFIED_IMAGE_LAYOUTS_FEATURES_KHR,
			unifiedImageLayouts	= true,
		}
		_vk_link(&extended_dynamic_state_2_features, &unified_image_layouts_features)
	}
	descriptor := vk.DeviceCreateInfo {
		sType			= .DEVICE_CREATE_INFO,
		pNext			= &device_features,
		queueCreateInfoCount	= cast(u32)len(queue_descriptors),
		pQueueCreateInfos	= raw_data(queue_descriptors),
		enabledExtensionCount	= cast(u32)len(_vk_enabled_device_extensions),
		ppEnabledExtensionNames	= raw_data(_vk_enabled_device_extensions[:]),
	}

	// log.debugf("Creating device with extensions: %v.", _vk_enabled_device_extensions)
	_vk_call(vk.CreateDevice(_vk_physical_device, &descriptor, nil, &_vk_device)) or_return

	_vk_setup_descriptor_pool() or_return
	_vk_setup_pipeline_layouts() or_return
	_vk_setup_pipeline_cache() or_return

	return nil
}

_vk_setup_pipeline_layouts :: proc() -> Result {
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
		pSetLayouts		= &_vk_descriptor_set_layout,
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
		pSetLayouts		= &_vk_descriptor_set_layout,
	}

	_vk_call(vk.CreatePipelineLayout(_vk_device, &compute_layout_info, nil, &_vk_compute_pipeline_layout)) or_return
	_vk_call(vk.CreatePipelineLayout(_vk_device, &render_layout_info, nil, &_vk_render_pipeline_layout)) or_return

	return nil
}

_vk_setup_pipeline_cache :: proc() -> Result {
	// TODO: Persistent pipeline cache
	pipeline_cache_info := vk.PipelineCacheCreateInfo {
		sType			= .PIPELINE_CACHE_CREATE_INFO,
		initialDataSize		= 0,
	}
	_vk_call(vk.CreatePipelineCache(_vk_device, &pipeline_cache_info, nil, &_vk_pipeline_cache)) or_return

	return nil
}

_vk_setup_descriptor_pool :: proc() -> Result {
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
	_vk_call(vk.CreateDescriptorPool(_vk_device, &descriptor_pool_info, nil, &_vk_descriptor_pool)) or_return

	descriptor_set_bindings := [_vk_Descriptor_Binding]vk.DescriptorSetLayoutBinding {
		.Sampler = {
			binding			= cast(u32)_vk_Descriptor_Binding.Sampler,
			descriptorType		= .SAMPLER,
			descriptorCount		= MAX_SAMPLERS_PER_SET,
			stageFlags		= { .VERTEX, .FRAGMENT, .COMPUTE },
		},
		.Texture_1d_Sampled_Image = {
			binding			= cast(u32)_vk_Descriptor_Binding.Texture_1d_Sampled_Image,
			descriptorType		= .SAMPLED_IMAGE,
			descriptorCount		= MAX_TEXTURES_PER_SET,
			stageFlags		= { .VERTEX, .FRAGMENT, .COMPUTE },
		},
		.Texture_2d_Sampled_Image = {
			binding			= cast(u32)_vk_Descriptor_Binding.Texture_2d_Sampled_Image,
			descriptorType		= .SAMPLED_IMAGE,
			descriptorCount		= MAX_TEXTURES_PER_SET,
			stageFlags		= { .VERTEX, .FRAGMENT, .COMPUTE },
		},
		.Texture_2d_Array_Sampled_Image = {
			binding			= cast(u32)_vk_Descriptor_Binding.Texture_2d_Array_Sampled_Image,
			descriptorType		= .SAMPLED_IMAGE,
			descriptorCount		= MAX_TEXTURES_PER_SET,
			stageFlags		= { .VERTEX, .FRAGMENT, .COMPUTE },
		},
		.Texture_Cube_Sampled_Image = {
			binding			= cast(u32)_vk_Descriptor_Binding.Texture_Cube_Sampled_Image,
			descriptorType		= .SAMPLED_IMAGE,
			descriptorCount		= MAX_TEXTURES_PER_SET,
			stageFlags		= { .VERTEX, .FRAGMENT, .COMPUTE },
		},
		.Texture_Cube_Array_Sampled_Image = {
			binding			= cast(u32)_vk_Descriptor_Binding.Texture_Cube_Array_Sampled_Image,
			descriptorType		= .SAMPLED_IMAGE,
			descriptorCount		= MAX_TEXTURES_PER_SET,
			stageFlags		= { .VERTEX, .FRAGMENT, .COMPUTE },
		},
		.Texture_3d_Sampled_Image = {
			binding			= cast(u32)_vk_Descriptor_Binding.Texture_3d_Sampled_Image,
			descriptorType		= .SAMPLED_IMAGE,
			descriptorCount		= MAX_TEXTURES_PER_SET,
			stageFlags		= { .VERTEX, .FRAGMENT, .COMPUTE },
		},
		.Texture_2d_Multisampled_Image = {
			binding			= cast(u32)_vk_Descriptor_Binding.Texture_2d_Multisampled_Image,
			descriptorType		= .SAMPLED_IMAGE,
			descriptorCount		= MAX_TEXTURES_PER_SET,
			stageFlags		= { .VERTEX, .FRAGMENT, .COMPUTE },
		},
		.Texture_2d_Array_Multisampled_Image = {
			binding			= cast(u32)_vk_Descriptor_Binding.Texture_2d_Array_Multisampled_Image,
			descriptorType		= .SAMPLED_IMAGE,
			descriptorCount		= MAX_TEXTURES_PER_SET,
			stageFlags		= { .VERTEX, .FRAGMENT, .COMPUTE },
		},
		.Texture_1d_Storage_Image = {
			binding			= cast(u32)_vk_Descriptor_Binding.Texture_1d_Storage_Image,
			descriptorType		= .STORAGE_IMAGE,
			descriptorCount		= MAX_TEXTURES_PER_SET,
			stageFlags		= { .VERTEX, .FRAGMENT, .COMPUTE },
		},
		.Texture_2d_Storage_Image = {
			binding			= cast(u32)_vk_Descriptor_Binding.Texture_2d_Storage_Image,
			descriptorType		= .STORAGE_IMAGE,
			descriptorCount		= MAX_TEXTURES_PER_SET,
			stageFlags		= { .VERTEX, .FRAGMENT, .COMPUTE },
		},
		.Texture_2d_Array_Storage_Image = {
			binding			= cast(u32)_vk_Descriptor_Binding.Texture_2d_Array_Storage_Image,
			descriptorType		= .STORAGE_IMAGE,
			descriptorCount		= MAX_TEXTURES_PER_SET,
			stageFlags		= { .VERTEX, .FRAGMENT, .COMPUTE },
		},
		.Texture_3d_Storage_Image = {
			binding			= cast(u32)_vk_Descriptor_Binding.Texture_3d_Storage_Image,
			descriptorType		= .STORAGE_IMAGE,
			descriptorCount		= MAX_TEXTURES_PER_SET,
			stageFlags		= { .VERTEX, .FRAGMENT, .COMPUTE },
		},
	}
	binding_flags := [_vk_Descriptor_Binding]vk.DescriptorBindingFlags {
		.Sampler				= { .PARTIALLY_BOUND, .UPDATE_AFTER_BIND },
		.Texture_1d_Sampled_Image		= { .PARTIALLY_BOUND, .UPDATE_AFTER_BIND },
		.Texture_1d_Storage_Image		= { .PARTIALLY_BOUND, .UPDATE_AFTER_BIND },
		.Texture_2d_Sampled_Image		= { .PARTIALLY_BOUND, .UPDATE_AFTER_BIND },
		.Texture_2d_Storage_Image		= { .PARTIALLY_BOUND, .UPDATE_AFTER_BIND },
		.Texture_2d_Array_Sampled_Image		= { .PARTIALLY_BOUND, .UPDATE_AFTER_BIND },
		.Texture_2d_Array_Storage_Image 	= { .PARTIALLY_BOUND, .UPDATE_AFTER_BIND },
		.Texture_2d_Multisampled_Image		= { .PARTIALLY_BOUND, .UPDATE_AFTER_BIND },
		.Texture_2d_Array_Multisampled_Image	= { .PARTIALLY_BOUND, .UPDATE_AFTER_BIND },
		.Texture_Cube_Sampled_Image		= { .PARTIALLY_BOUND, .UPDATE_AFTER_BIND },
		.Texture_Cube_Array_Sampled_Image	= { .PARTIALLY_BOUND, .UPDATE_AFTER_BIND },
		.Texture_3d_Sampled_Image		= { .PARTIALLY_BOUND, .UPDATE_AFTER_BIND },
		.Texture_3d_Storage_Image		= { .PARTIALLY_BOUND, .UPDATE_AFTER_BIND },
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
	_vk_call(
		vk.CreateDescriptorSetLayout(_vk_device, &descriptor_set_layout_info, nil, &_vk_descriptor_set_layout),
	) or_return

	return nil
}

_vk_device_info_of :: proc(device: vk.PhysicalDevice) -> (info: Device_Info, res: Result) {
	_vk_info := &info._platform.vk

	extension_count: u32
	_vk_call(vk.EnumerateDeviceExtensionProperties(device, nil, &extension_count, nil)) or_return
	_vk_info.extensions = make([]vk.ExtensionProperties, extension_count, _global_allocator)
	_vk_call(vk.EnumerateDeviceExtensionProperties(device, nil, &extension_count, raw_data(_vk_info.extensions))) or_return

	_vk_info.physical_device		= device

	_vk_info.properties.sType	= .PHYSICAL_DEVICE_PROPERTIES_2
	_vk_info.properties.pNext	= &_vk_info.properties_11
	_vk_info.properties_11.sType	= .PHYSICAL_DEVICE_VULKAN_1_1_PROPERTIES
	_vk_info.properties_11.pNext	= &_vk_info.properties_12
	_vk_info.properties_12.sType	= .PHYSICAL_DEVICE_VULKAN_1_2_PROPERTIES
	vk.GetPhysicalDeviceProperties2(device, &_vk_info.properties)

	_vk_info.features.sType		= .PHYSICAL_DEVICE_FEATURES_2
	_vk_info.features.pNext		= &_vk_info.features_11
	_vk_info.features_11.sType	= .PHYSICAL_DEVICE_VULKAN_1_1_FEATURES
	_vk_info.features_11.pNext	= &_vk_info.features_12
	_vk_info.features_12.sType	= .PHYSICAL_DEVICE_VULKAN_1_2_FEATURES
	_vk_info.features_12.pNext	= &_vk_info.dynamic_rendering_features
	_vk_info.dynamic_rendering_features.sType	= .PHYSICAL_DEVICE_DYNAMIC_RENDERING_FEATURES_KHR
	_vk_info.dynamic_rendering_features.pNext	= &_vk_info.synchronization2_features
	_vk_info.synchronization2_features.sType		= .PHYSICAL_DEVICE_SYNCHRONIZATION_2_FEATURES
	vk.GetPhysicalDeviceFeatures2(device, &_vk_info.features)

	_vk_find_memory_types(device, &info)
	_vk_find_queue_families(device, &info)

	info.name = strings.clone_from_cstring_bounded(
		cast(cstring)&_vk_info.properties.properties.deviceName[0],
		len(_vk_info.properties.properties.deviceName),
		_global_allocator,
	)
	info.driver = strings.clone_from_cstring_bounded(
		cast(cstring)&_vk_info.properties_12.driverName[0],
		len(_vk_info.properties_12.driverName),
		_global_allocator,
	)
	info.type = _vk_PHYSICAL_DEVICE_TYPE_TO_GFX[_vk_info.properties.properties.deviceType]

	info.limits.allocation_alignment	= 16 * mem.Kilobyte
	info.limits.min_allocation_size		= 16 * mem.Kilobyte
	info.properties.transfer_queue		= _vk_info.has_transfer_queue_family

	return
}

_vk_device_has_extension :: proc(info: ^Device_Info, extension: string) -> bool {
	_vk_info := &info._platform.vk

	for &property in _vk_info.extensions {
		if strings.string_from_null_terminated_ptr(
			raw_data(property.extensionName[:]),
			len(property.extensionName),
		) == extension {
			
			return true
		}
	}

	return false
}

_vk_find_memory_types :: proc(device: vk.PhysicalDevice, info: ^Device_Info) {
	_vk_info := &info._platform.vk
	
	_vk_info.memory_properties.sType = .PHYSICAL_DEVICE_MEMORY_PROPERTIES_2
	vk.GetPhysicalDeviceMemoryProperties2(device, &_vk_info.memory_properties)

	_vk_info.private_memory, _vk_info.has_private_memory = _vk_search_for_memory_type(info, { .DEVICE_LOCAL })

	_vk_info.shared_memory, _vk_info.has_shared_memory =
		_vk_search_for_memory_type(info, { .DEVICE_LOCAL, .HOST_VISIBLE, .HOST_COHERENT })
	if !_vk_info.has_shared_memory {
		_vk_info.shared_memory, _vk_info.has_shared_memory =
			_vk_search_for_memory_type(info, { .HOST_VISIBLE, .HOST_COHERENT })
	} else {
		info.properties.host_accessible_device_memory = true
	}

	_vk_info.updown_memory, _vk_info.has_updown_memory =
		_vk_search_for_memory_type(info, { .DEVICE_LOCAL, .HOST_VISIBLE, .HOST_COHERENT })
	updown_memory_size := _vk_info.memory_properties.memoryProperties.memoryHeaps[
		_vk_info.memory_properties.memoryProperties.memoryTypes[_vk_info.updown_memory].heapIndex].size
	if !_vk_info.has_updown_memory || updown_memory_size < 512 * mem.Megabyte {
		_vk_info.updown_memory, _vk_info.has_updown_memory =
			_vk_search_for_memory_type(info, { .HOST_VISIBLE, .HOST_COHERENT })
	}
}

_vk_search_for_memory_type :: proc(info: ^Device_Info, properties: vk.MemoryPropertyFlags) -> (type_idx: u32, found: bool) {
	_vk_info := &info._platform.vk
	memory_properties := &_vk_info.memory_properties.memoryProperties

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

_vk_find_queue_families :: proc(device: vk.PhysicalDevice, info: ^Device_Info) {
	_vk_info := &info._platform.vk

	queue_family_count: u32
	vk.GetPhysicalDeviceQueueFamilyProperties2(device, &queue_family_count, nil)

	resize(&_vk_info.queue_families, queue_family_count)
	for &family in _vk_info.queue_families {
		family.sType = .QUEUE_FAMILY_PROPERTIES_2
	}
	vk.GetPhysicalDeviceQueueFamilyProperties2(device, &queue_family_count, raw_data(_vk_info.queue_families[:]))

	_vk_info.has_default_queue_family = false
	for queue, i in _vk_info.queue_families {
		if .TRANSFER not_in queue.queueFamilyProperties.queueFlags ||
			.COMPUTE not_in queue.queueFamilyProperties.queueFlags ||
			.GRAPHICS not_in queue.queueFamilyProperties.queueFlags {

			continue
		}

		_vk_info.default_queue_family = cast(u32)i
		_vk_info.has_default_queue_family = true
		break
	}

	if !_vk_info.has_default_queue_family {
		return
	}

	for queue, i in _vk_info.queue_families {
		if .TRANSFER not_in queue.queueFamilyProperties.queueFlags ||
			cast(u32)i == _vk_info.default_queue_family {
			
			continue
		}

		if .COMPUTE not_in queue.queueFamilyProperties.queueFlags &&
			.GRAPHICS not_in queue.queueFamilyProperties.queueFlags {
			
			_vk_info.transfer_queue_family = cast(u32)i
			_vk_info.has_transfer_queue_family = true
			break
		}

		if !_vk_info.has_transfer_queue_family {
			_vk_info.transfer_queue_family = cast(u32)i
			_vk_info.has_transfer_queue_family = true
		}
	}

	// NOTE: If we couln't find a different queue family for transfer, then let's try to use the default one as
	//	transfer.
	// if !_vk_info.has_transfer_queue_family {
	// 	if _vk_info.queue_families[_vk_info.default_queue_family].queueFamilyProperties.queueCount > 1 {
	// 		_vk_info.transfer_queue_family = _vk_info.default_queue_family
	// 	}
	// }
}

_vk_is_device_suitable :: proc(device: vk.PhysicalDevice, info: ^Device_Info) -> bool {
	_vk_info := &info._platform.vk

	return _vk_device_has_extension(info, "VK_KHR_dynamic_rendering") &&
		_vk_device_has_extension(info, "VK_KHR_synchronization2") &&
		_vk_device_has_extension(info, "VK_EXT_extended_dynamic_state") &&
		_vk_device_has_extension(info, "VK_EXT_extended_dynamic_state2") &&
		_vk_device_has_extension(info, "VK_KHR_swapchain") &&
		_vk_info.features.features.imageCubeArray == true &&
		_vk_info.features.features.samplerAnisotropy == true &&
		_vk_info.features.features.shaderSampledImageArrayDynamicIndexing == true &&
		_vk_info.features.features.shaderStorageImageArrayDynamicIndexing == true &&
		_vk_info.features.features.shaderStorageImageReadWithoutFormat == true &&
		_vk_info.features.features.shaderStorageImageWriteWithoutFormat == true &&
		_vk_info.features.features.shaderInt16 == true &&
		_vk_info.features_11.shaderDrawParameters == true &&
		_vk_info.features_12.timelineSemaphore == true &&
		_vk_info.features_12.bufferDeviceAddress == true &&
		_vk_info.features_12.runtimeDescriptorArray == true &&
		_vk_info.features_12.descriptorBindingPartiallyBound == true &&
		_vk_info.features_12.descriptorBindingStorageImageUpdateAfterBind == true &&
		_vk_info.features_12.descriptorBindingSampledImageUpdateAfterBind == true &&
		_vk_info.features_12.descriptorBindingUpdateUnusedWhilePending == true &&
		_vk_info.features_12.shaderSampledImageArrayNonUniformIndexing == true &&
		_vk_info.features_12.shaderStorageImageArrayNonUniformIndexing == true &&
		_vk_info.features_12.shaderInt8 == true &&
		_vk_info.synchronization2_features.synchronization2 == true &&
		_vk_info.dynamic_rendering_features.dynamicRendering == true &&
		_vk_info.has_default_queue_family &&
		_vk_info.has_private_memory &&
		_vk_info.has_updown_memory &&
		_vk_info.has_shared_memory
}

@(rodata)
_vk_PHYSICAL_DEVICE_TYPE_TO_GFX := [vk.PhysicalDeviceType]Device_Type {
	.OTHER		= .Other,
	.INTEGRATED_GPU	= .Integrated,
	.DISCRETE_GPU	= .Discrete,
	.VIRTUAL_GPU	= .Other,
	.CPU		= .Other,
}

