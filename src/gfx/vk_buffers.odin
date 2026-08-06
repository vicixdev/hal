package gfx

import "core:fmt"
import vk "vendor:vulkan"

vk_Buffer_Metadata :: struct {
	device_memory:	vk.DeviceMemory,
	buffer:		vk.Buffer,
}

vk_alloc :: proc(metadata: ^_Buffer_Metadata, type: Memory, size: int) -> (res: Result) {

	memory_type := type == .Private ? vk_device_info.private_memory : vk_device_info.shared_memory

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
	vk_call(vk.AllocateMemory(vk_device, &allocate_info, nil, &memory)) or_return
	defer if res != nil do vk.FreeMemory(vk_device, memory, nil)

	queue_family_indices: []u32
	if vk_device_info.has_transfer_queue_family {
		queue_family_indices =
			{ vk_device_info.default_queue_family, vk_device_info.transfer_queue_family }
	} else {
		queue_family_indices = { vk_device_info.default_queue_family }
	}

	buffer_info := vk.BufferCreateInfo {
		sType	= .BUFFER_CREATE_INFO,
		size	= cast(vk.DeviceSize)size,
		usage	= {
			.TRANSFER_SRC,
			.TRANSFER_DST,
			.STORAGE_BUFFER,
			.INDIRECT_BUFFER,
			.SHADER_DEVICE_ADDRESS_KHR,
		},
		sharingMode		= .EXCLUSIVE,
		queueFamilyIndexCount	= cast(u32)len(queue_family_indices),
		pQueueFamilyIndices	= raw_data(queue_family_indices),
	}

	buffer: vk.Buffer
	vk_call(vk.CreateBuffer(vk_device, &buffer_info, nil, &buffer)) or_return
	defer if res != nil do vk.DestroyBuffer(vk_device, buffer, nil)

	vk_call(vk.BindBufferMemory(vk_device, buffer, memory, 0)) or_return

	buffer_address_info := vk.BufferDeviceAddressInfo {
		sType	= .BUFFER_DEVICE_ADDRESS_INFO,
		buffer	= buffer,
	}
	gpu_address := vk.GetBufferDeviceAddress(vk_device, &buffer_address_info)

	cpu_address: rawptr
	if type != .Private {
		vk_call(vk.MapMemory(vk_device, memory, 0, cast(vk.DeviceSize)size, {}, &cpu_address)) or_return
	}

	metadata.cpu_address		= cast(uintptr)cpu_address
	metadata.gpu_address		= cast(uintptr)gpu_address
	metadata.vk.device_memory	= memory
	metadata.vk.buffer		= buffer

	return nil
}

vk_dealloc :: proc(metadata: ^_Buffer_Metadata) {
	if metadata.memory_type != .Private {
		vk.UnmapMemory(vk_device, metadata.vk.device_memory)
	}

	vk.DestroyBuffer(vk_device, metadata.vk.buffer, nil)
	vk.FreeMemory(vk_device, metadata.vk.device_memory, nil)
}

vk_mark_as_modified :: proc(metadata: ^_Buffer_Metadata, buffer: Buffer, length: int) -> Result {
	if _device_info.properties.coherent_memory {
		return nil
	}

	memory_range := vk.MappedMemoryRange {
		sType	= .MAPPED_MEMORY_RANGE,
		memory	= metadata.vk.device_memory,
		offset	= cast(vk.DeviceSize)_offset_from_base(buffer, metadata),
		size	= cast(vk.DeviceSize)length,
	}
	vk_call(vk.FlushMappedMemoryRanges(vk_device, 1, &memory_range)) or_return

	return nil
}

vk_prepare_for_readback :: proc(metadata: ^_Buffer_Metadata, buffer: Buffer, length: int) -> Result {
	if _device_info.properties.coherent_memory {
		return nil
	}

	memory_range := vk.MappedMemoryRange {
		sType	= .MAPPED_MEMORY_RANGE,
		memory	= metadata.vk.device_memory,
		offset	= cast(vk.DeviceSize)_offset_from_base(buffer, metadata),
		size	= cast(vk.DeviceSize)length,
	}
	vk_call(vk.InvalidateMappedMemoryRanges(vk_device, 1, &memory_range)) or_return

	return nil
}

vk_label_buffer :: proc(metadata: ^_Buffer_Metadata, label: string) -> Result {
	context.temp_allocator = _temp_allocator

	vk_label_object(metadata.vk.buffer, .BUFFER, fmt.ctprint("%s (Buffer)", label)) or_return
	vk_label_object(metadata.vk.device_memory, .DEVICE_MEMORY, fmt.ctprint("%s (Device memory)", label)) or_return

	return nil
}

