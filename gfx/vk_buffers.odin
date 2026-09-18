package vicixdev_gfx

/*
This Source Code Form is subject to the terms of the Mozilla Public
License, v. 2.0. If a copy of the MPL was not distributed with this
file, You can obtain one at https://mozilla.org/MPL/2.0/.
*/



import "core:fmt"
import vk "vendor:vulkan"

_vk_Buffer_Metadata :: struct {
	device_memory:	vk.DeviceMemory,
	buffer:		vk.Buffer,
}

_vk_alloc :: proc(metadata: ^_Buffer_Metadata, type: Memory, size: int) -> (res: Result) {

	memory_type: u32
	switch type {
	case .Default: memory_type	= _vk_device_info.shared_memory
	case .Private: memory_type	= _vk_device_info.private_memory
	case .Readback: memory_type	= _vk_device_info.updown_memory
	case .Staging:	memory_type	= _vk_device_info.updown_memory
	}

	allocate_flags_info := vk.MemoryAllocateFlagsInfo {
		sType	= .MEMORY_ALLOCATE_FLAGS_INFO,
		flags	= { .DEVICE_ADDRESS },
	}
	allocate_info := vk.MemoryAllocateInfo {
		sType		= .MEMORY_ALLOCATE_INFO,
		pNext		= &allocate_flags_info,
		memoryTypeIndex	= memory_type,
		allocationSize	= cast(vk.DeviceSize)size,
	}

	memory: vk.DeviceMemory
	_vk_call(vk.AllocateMemory(_vk_device, &allocate_info, nil, &memory)) or_return
	defer if res != nil do vk.FreeMemory(_vk_device, memory, nil)

	queue_family_indices: []u32
	if _vk_device_info.has_transfer_queue_family {
		queue_family_indices =
			{ _vk_device_info.default_queue_family, _vk_device_info.transfer_queue_family }
	} else {
		queue_family_indices = { _vk_device_info.default_queue_family }
	}

	sharing_mode := len(queue_family_indices) > 1 ? vk.SharingMode.CONCURRENT : vk.SharingMode.EXCLUSIVE

	buffer_info := vk.BufferCreateInfo {
		sType	= .BUFFER_CREATE_INFO,
		size	= cast(vk.DeviceSize)size,
		usage	= {
			.INDEX_BUFFER,
			.TRANSFER_SRC,
			.TRANSFER_DST,
			.STORAGE_BUFFER,
			.INDIRECT_BUFFER,
			.SHADER_DEVICE_ADDRESS_KHR,
		},
		sharingMode		= sharing_mode,
		queueFamilyIndexCount	= cast(u32)len(queue_family_indices),
		pQueueFamilyIndices	= raw_data(queue_family_indices),
	}

	buffer: vk.Buffer
	_vk_call(vk.CreateBuffer(_vk_device, &buffer_info, nil, &buffer)) or_return
	defer if res != nil do vk.DestroyBuffer(_vk_device, buffer, nil)

	_vk_call(vk.BindBufferMemory(_vk_device, buffer, memory, 0)) or_return

	buffer_address_info := vk.BufferDeviceAddressInfo {
		sType	= .BUFFER_DEVICE_ADDRESS_INFO,
		buffer	= buffer,
	}
	gpu_address := vk.GetBufferDeviceAddress(_vk_device, &buffer_address_info)

	cpu_address: rawptr
	if type != .Private {
		_vk_call(vk.MapMemory(_vk_device, memory, 0, cast(vk.DeviceSize)size, {}, &cpu_address)) or_return
	}

	metadata.cpu_address		= cast(uintptr)cpu_address
	metadata.gpu_address		= cast(uintptr)gpu_address
	metadata.vk.device_memory	= memory
	metadata.vk.buffer		= buffer

	return nil
}

_vk_dealloc :: proc(metadata: ^_Buffer_Metadata) {
	if metadata.memory_type != .Private {
		vk.UnmapMemory(_vk_device, metadata.vk.device_memory)
	}

	vk.DestroyBuffer(_vk_device, metadata.vk.buffer, nil)
	vk.FreeMemory(_vk_device, metadata.vk.device_memory, nil)
}

_vk_label_buffer :: proc(metadata: ^_Buffer_Metadata, label: string) -> Result {
	context.temp_allocator = _temp_allocator

	_vk_label_object(metadata.vk.buffer, .BUFFER, fmt.ctprint("%s (Buffer)", label)) or_return
	_vk_label_object(metadata.vk.device_memory, .DEVICE_MEMORY, fmt.ctprint("%s (Device memory)", label)) or_return

	return nil
}

