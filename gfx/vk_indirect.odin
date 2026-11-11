package vicixdev_gfx

import vk "vendor:vulkan"
import "core:sync"

_vk_encode_dispatch_pso: vk.Pipeline
_vk_prepare_draw_encoding_dispatch_pso: vk.Pipeline
_vk_prepare_draw_encoding_dispatch_count_pso: vk.Pipeline
_vk_encode_draw_pso: vk.Pipeline
_vk_encode_indexed_draw_pso: vk.Pipeline

_VK_INDIRECT_COMMAND_STRIDE :: max(
	size_of(vk.DrawIndirectCommand),
	size_of(vk.DrawIndexedIndirectCommand),
)

_vk_Indirect_Command_Pool_Metadata :: struct {
	/*
		GPU buffer layout:
		Dispatch pool:
			[0] VkDispatchIndirectCommand[command_count]
		Draw pool:
			[0] VkDispatchIndirectCommand[command_count]
			[dispatch bytes] VkDraw(Indexed)IndirectCommand[
				command_count * max_call_count_per_command
			]

		Each command gets one fixed draw-command slot containing
		max_call_count_per_command entries.
	*/
	buffer:		vk.Buffer,
	memory:		vk.DeviceMemory,
	address:	uintptr,
	index:		int,
}

_vk_Indirect_Command_Metadata :: struct {
	slot: int,
}

_vk_init_indirect :: proc() -> Result {
	_vk_encode_dispatch_pso		= _vk_compile_internal_compute_kernel("encode_dispatch")
	_vk_prepare_draw_encoding_dispatch_pso		= _vk_compile_internal_compute_kernel("prepare_draw_encoding_dispatch")
	_vk_prepare_draw_encoding_dispatch_count_pso	= _vk_compile_internal_compute_kernel("prepare_draw_encoding_dispatch_count")
	_vk_encode_draw_pso		= _vk_compile_internal_compute_kernel("encode_draw")
	_vk_encode_indexed_draw_pso	= _vk_compile_internal_compute_kernel("encode_indexed_draw")

	return nil
}

_vk_fini_indirect :: proc() {
	vk.DestroyPipeline(_vk_device, _vk_encode_dispatch_pso, nil)
	vk.DestroyPipeline(_vk_device, _vk_prepare_draw_encoding_dispatch_pso, nil)
	vk.DestroyPipeline(_vk_device, _vk_prepare_draw_encoding_dispatch_count_pso, nil)
	vk.DestroyPipeline(_vk_device, _vk_encode_draw_pso, nil)
	vk.DestroyPipeline(_vk_device, _vk_encode_indexed_draw_pso, nil)
}

_vk_create_indirect_command_pool :: proc(
	metadata:	^_Indirect_Command_Pool_Metadata,
	descriptor:	Indirect_Command_Pool_Descriptor,
) -> (res: Result) {
	switch descriptor.type {
	case .Dispatch:
		return _vk_create_dispatch_icp(metadata, descriptor)
	case .Draw:
		return _vk_create_draw_icp(metadata, descriptor)
	}
	unreachable()
}

_vk_create_dispatch_icp :: proc(
	metadata: ^_Indirect_Command_Pool_Metadata,
	descriptor: Indirect_Command_Pool_Descriptor,
) -> (res: Result) {
	size := _vk_size_of_dispatch_pool(descriptor)
	metadata.vk.buffer, metadata.vk.memory, metadata.vk.address = _vk_create_icp_buffer(size) or_return

	return nil
}

_vk_create_draw_icp :: proc(
	metadata: ^_Indirect_Command_Pool_Metadata,
	descriptor: Indirect_Command_Pool_Descriptor,
) -> (res: Result) {
	size := _vk_size_of_draw_pool(descriptor)
	metadata.vk.buffer, metadata.vk.memory, metadata.vk.address = _vk_create_icp_buffer(size) or_return

	return nil
}

_vk_size_of_dispatch_pool :: proc(descriptor: Indirect_Command_Pool_Descriptor) -> int {
	return descriptor.command_count * size_of(vk.DispatchIndirectCommand)
}

_vk_size_of_draw_pool :: proc(descriptor: Indirect_Command_Pool_Descriptor) -> int {
	return cast(int)_vk_draw_icp_draw_commands_offset(descriptor.command_count) +
		descriptor.command_count * descriptor.max_call_count_per_command * _VK_INDIRECT_COMMAND_STRIDE
}

_vk_create_icp_buffer :: proc(
	size: int,
) -> (buffer: vk.Buffer, memory: vk.DeviceMemory, address: uintptr, res: Result) {

	queue_family_indices: []u32
	if _vk_device_info.has_transfer_queue_family {
		queue_family_indices = { _vk_device_info.default_queue_family, _vk_device_info.transfer_queue_family }
	} else {
		queue_family_indices = { _vk_device_info.default_queue_family }
	}

	buffer_info := vk.BufferCreateInfo {
		sType = .BUFFER_CREATE_INFO,
		size = cast(vk.DeviceSize)size,
		usage = { .STORAGE_BUFFER, .INDIRECT_BUFFER, .SHADER_DEVICE_ADDRESS, .TRANSFER_DST },
		sharingMode = len(queue_family_indices) > 1 ? .CONCURRENT : .EXCLUSIVE,
		queueFamilyIndexCount = cast(u32)len(queue_family_indices),
		pQueueFamilyIndices = raw_data(queue_family_indices),
	}
	_vk_call(vk.CreateBuffer(_vk_device, &buffer_info, nil, &buffer)) or_return
	defer if res != nil do vk.DestroyBuffer(_vk_device, buffer, nil)

	requirements: vk.MemoryRequirements
	vk.GetBufferMemoryRequirements(_vk_device, buffer, &requirements)

	allocate_flags := vk.MemoryAllocateFlagsInfo {
		sType = .MEMORY_ALLOCATE_FLAGS_INFO,
		flags = { .DEVICE_ADDRESS },
	}
	allocate_info := vk.MemoryAllocateInfo {
		sType = .MEMORY_ALLOCATE_INFO,
		pNext = &allocate_flags,
		memoryTypeIndex = _vk_device_info.private_memory,
		allocationSize = requirements.size,
	}
	_vk_call(vk.AllocateMemory(_vk_device, &allocate_info, nil, &memory)) or_return
	defer if res != nil do vk.FreeMemory(_vk_device, memory, nil)
	_vk_call(vk.BindBufferMemory(_vk_device, buffer, memory, 0)) or_return

	address_info := vk.BufferDeviceAddressInfo {
		sType = .BUFFER_DEVICE_ADDRESS_INFO,
		buffer = buffer,
	}
	address = cast(uintptr)vk.GetBufferDeviceAddress(_vk_device, &address_info)

	return buffer, memory, address, nil
}

_vk_destroy_indirect_command_pool :: proc(metadata: ^_Indirect_Command_Pool_Metadata) {
	vk.DestroyBuffer(_vk_device, metadata.vk.buffer, nil)
	vk.FreeMemory(_vk_device, metadata.vk.memory, nil)
}

_vk_prepare_indirect_command :: proc(
	icp_metadata:	^_Indirect_Command_Pool_Metadata,
	ic_metadata:	^_Indirect_Command_Metadata,
) -> Result {
	ic_metadata.vk.slot = _vk_icp_scratch_alloc_slot(icp_metadata)

	return nil
}

_vk_emit_encode_indirect :: proc(
	metadata:	^_Command_Buffer_Metadata,
	queue_metadata:	^_Queue_Metadata,
	command:	_Command_Encode_Indirect,
) -> Result {
	ic_metadata, res := _metadata_of(command.command)
	_check_internal_emission_result(res) or_return
	icp_metadata, icp_res := _metadata_of(ic_metadata.pool)
	_check_internal_emission_result(icp_res) or_return

	switch ic_metadata.type {
	case .Dispatch:
		_vk_emit_encode_dispatch_indirect(metadata, icp_metadata, ic_metadata)
	case .Draw, .Draw_Count:
		_vk_emit_encode_draw_indirect(metadata, icp_metadata, ic_metadata)
	case .Draw_Indexed, .Draw_Indexed_Count:
		_vk_emit_encode_draw_indexed_indirect(metadata, icp_metadata, ic_metadata)
	}

	return nil
}

_vk_emit_encode_dispatch_indirect :: proc(
	metadata: ^_Command_Buffer_Metadata,
	icp_metadata: ^_Indirect_Command_Pool_Metadata,
	ic_metadata: ^_Indirect_Command_Metadata,
) {
	_vk_Encode_Dispatch_Arguments :: struct #packed {
		source:		uintptr,
		destination:	uintptr,
	}

	source := cast(uintptr)ic_metadata.dispatch.indirect_parameters
	destination := icp_metadata.vk.address + _vk_dispatch_icp_indirect_command_offset(ic_metadata)

	vk.CmdBindPipeline(metadata.vk.command_buffer, .COMPUTE, _vk_encode_dispatch_pso)
	arguments := _vk_Encode_Dispatch_Arguments{
		source = source,
		destination = destination,
	}
	vk.CmdPushConstants(metadata.vk.command_buffer, _vk_compute_pipeline_layout, { .COMPUTE }, 0, size_of(arguments), &arguments)
	vk.CmdDispatch(metadata.vk.command_buffer, 1, 1, 1)
}

_vk_emit_encode_draw_indirect :: proc(
	metadata: ^_Command_Buffer_Metadata,
	icp_metadata: ^_Indirect_Command_Pool_Metadata,
	ic_metadata: ^_Indirect_Command_Metadata,
) {
	_vk_Encode_Draw_Arguments :: struct #packed {
		source: uintptr,
		destination: uintptr,
	}

	_vk_emit_icp_prepare_draw_encoding_dispatch(metadata, icp_metadata, ic_metadata)

	barrier_info := vk.DependencyInfo {
		sType = .DEPENDENCY_INFO,
		bufferMemoryBarrierCount = 1,
		pBufferMemoryBarriers = &vk.BufferMemoryBarrier2 {
			sType = .BUFFER_MEMORY_BARRIER_2,
			srcStageMask = { .COMPUTE_SHADER },
			srcAccessMask = { .SHADER_STORAGE_WRITE },
			dstStageMask = { .DRAW_INDIRECT },
			dstAccessMask = { .INDIRECT_COMMAND_READ },
			srcQueueFamilyIndex = vk.QUEUE_FAMILY_IGNORED,
			dstQueueFamilyIndex = vk.QUEUE_FAMILY_IGNORED,
			buffer = icp_metadata.vk.buffer,
			offset = cast(vk.DeviceSize)_vk_draw_icp_indirect_dispatch_offset(icp_metadata, ic_metadata),
			size = size_of(vk.DispatchIndirectCommand),
		},
	}
	vk.CmdPipelineBarrier2KHR(metadata.vk.command_buffer, &barrier_info)

	vk.CmdBindPipeline(metadata.vk.command_buffer, .COMPUTE, _vk_encode_draw_pso)
	source := cast(uintptr)ic_metadata.draw.indirect_parameters
	if ic_metadata.type == .Draw_Count {
		source = cast(uintptr)ic_metadata.draw_count.indirect_parameters
	}
	encode_arguments := _vk_Encode_Draw_Arguments {
		source = source,
		destination = icp_metadata.vk.address + _vk_draw_icp_draw_command_offset(icp_metadata, ic_metadata),
	}
	vk.CmdPushConstants(metadata.vk.command_buffer, _vk_compute_pipeline_layout, { .COMPUTE }, 0, size_of(encode_arguments), &encode_arguments)
	vk.CmdDispatchIndirect(metadata.vk.command_buffer, icp_metadata.vk.buffer,
		cast(vk.DeviceSize)_vk_draw_icp_indirect_dispatch_offset(icp_metadata, ic_metadata))
}

_vk_emit_encode_draw_indexed_indirect :: proc(
	metadata: ^_Command_Buffer_Metadata,
	icp_metadata: ^_Indirect_Command_Pool_Metadata,
	ic_metadata: ^_Indirect_Command_Metadata,
) {

	_vk_Encode_Indexed_Draw_Arguments :: struct #packed {
		source: uintptr,
		destination: uintptr,
	}

	_vk_emit_icp_prepare_draw_encoding_dispatch(metadata, icp_metadata, ic_metadata)

	barrier_info := vk.DependencyInfo {
		sType = .DEPENDENCY_INFO,
		bufferMemoryBarrierCount = 1,
		pBufferMemoryBarriers = &vk.BufferMemoryBarrier2 {
			sType = .BUFFER_MEMORY_BARRIER_2,
			srcStageMask = { .COMPUTE_SHADER },
			srcAccessMask = { .SHADER_STORAGE_WRITE },
			dstStageMask = { .DRAW_INDIRECT },
			dstAccessMask = { .INDIRECT_COMMAND_READ },
			srcQueueFamilyIndex = vk.QUEUE_FAMILY_IGNORED,
			dstQueueFamilyIndex = vk.QUEUE_FAMILY_IGNORED,
			buffer = icp_metadata.vk.buffer,
			offset = cast(vk.DeviceSize)_vk_draw_icp_indirect_dispatch_offset(icp_metadata, ic_metadata),
			size = size_of(vk.DispatchIndirectCommand),
		},
	}
	vk.CmdPipelineBarrier2KHR(metadata.vk.command_buffer, &barrier_info)

	vk.CmdBindPipeline(metadata.vk.command_buffer, .COMPUTE, _vk_encode_indexed_draw_pso)
	source := cast(uintptr)ic_metadata.draw_indexed.indirect_parameters
	if ic_metadata.type == .Draw_Indexed_Count {
		source = cast(uintptr)ic_metadata.draw_indexed_count.indirect_parameters
	}
	encode_arguments := _vk_Encode_Indexed_Draw_Arguments {
		source = source,
		destination = icp_metadata.vk.address + _vk_draw_icp_draw_command_offset(icp_metadata, ic_metadata),
	}
	vk.CmdPushConstants(metadata.vk.command_buffer, _vk_compute_pipeline_layout, { .COMPUTE }, 0, size_of(encode_arguments), &encode_arguments)
	vk.CmdDispatchIndirect(metadata.vk.command_buffer, icp_metadata.vk.buffer,
		cast(vk.DeviceSize)_vk_draw_icp_indirect_dispatch_offset(icp_metadata, ic_metadata))
}

_vk_emit_icp_prepare_draw_encoding_dispatch :: proc(
	metadata: ^_Command_Buffer_Metadata,
	icp_metadata: ^_Indirect_Command_Pool_Metadata,
	ic_metadata: ^_Indirect_Command_Metadata,
) {
	_vk_Prepare_Draw_Encoding_Dispatch_Arguments :: struct #packed {
		dispatch: uintptr,
		count: u32,
	}
	_vk_Prepare_Draw_Encoding_Dispatch_Count_Arguments :: struct #packed {
		dispatch: uintptr,
		count: uintptr,
	}

	dispatch := icp_metadata.vk.address + _vk_draw_icp_indirect_dispatch_offset(icp_metadata, ic_metadata)

	switch ic_metadata.type {
	case .Draw_Count, .Draw_Indexed_Count:
		vk.CmdBindPipeline(metadata.vk.command_buffer, .COMPUTE, _vk_prepare_draw_encoding_dispatch_count_pso)

		count := ic_metadata.draw_count.count
		if ic_metadata.type == .Draw_Indexed_Count {
			count = ic_metadata.draw_indexed_count.count
		}
		arguments := _vk_Prepare_Draw_Encoding_Dispatch_Count_Arguments {
			dispatch = dispatch,
			count = cast(uintptr)count,
		}
		vk.CmdPushConstants(metadata.vk.command_buffer, _vk_compute_pipeline_layout, { .COMPUTE }, 0, size_of(arguments), &arguments)
	case .Draw, .Draw_Indexed:
		vk.CmdBindPipeline(metadata.vk.command_buffer, .COMPUTE, _vk_prepare_draw_encoding_dispatch_pso)

		count := ic_metadata.draw.count
		if ic_metadata.type == .Draw_Indexed {
			count = ic_metadata.draw_indexed.count
		}
		arguments := _vk_Prepare_Draw_Encoding_Dispatch_Arguments {
			dispatch = dispatch,
			count = cast(u32)count,
		}
		vk.CmdPushConstants(metadata.vk.command_buffer, _vk_compute_pipeline_layout, { .COMPUTE }, 0, size_of(arguments), &arguments)
	case .Dispatch:
		unreachable()
	}
	vk.CmdDispatch(metadata.vk.command_buffer, 1, 1, 1)
}

_vk_emit_execute_indirect :: proc(
	metadata:	^_Command_Buffer_Metadata,
	queue_metadata:	^_Queue_Metadata,
	command:	_Command_Execute_Indirect,
) -> Result {
	ic_metadata, res := _metadata_of(command.command)
	_check_internal_emission_result(res) or_return
	icp_metadata, icp_res := _metadata_of(ic_metadata.pool)
	_check_internal_emission_result(icp_res) or_return

	switch ic_metadata.type {
	case .Dispatch:
		return _vk_emit_execute_dispatch_indirect(metadata, command, icp_metadata, ic_metadata)
	case .Draw, .Draw_Count:
		return _vk_emit_execute_draw_indirect(metadata, command, icp_metadata, ic_metadata)

	case .Draw_Indexed, .Draw_Indexed_Count:
		return _vk_emit_execute_draw_indexed_indirect(metadata, command, icp_metadata, ic_metadata)
	}
	return nil
}

_vk_emit_execute_dispatch_indirect :: proc(
	metadata: ^_Command_Buffer_Metadata,
	command: _Command_Execute_Indirect,
	icp_metadata: ^_Indirect_Command_Pool_Metadata,
	ic_metadata: ^_Indirect_Command_Metadata,
) -> Result {

	_, pipeline_res := _metadata_of(ic_metadata.dispatch.compute_pipeline)
	_check_internal_emission_result(pipeline_res) or_return

	arguments := cast(uintptr)ic_metadata.dispatch.arguments

	_vk_use_resource_set(metadata, command.resource_set) or_return
	_vk_use_compute_pipeline(metadata, ic_metadata.dispatch.compute_pipeline) or_return
	vk.CmdPushConstants(metadata.vk.command_buffer, _vk_compute_pipeline_layout, { .COMPUTE }, 0, size_of(uintptr), &arguments)
	vk.CmdDispatchIndirect(
		metadata.vk.command_buffer,
		icp_metadata.vk.buffer,
		cast(vk.DeviceSize)_vk_dispatch_icp_indirect_command_offset(ic_metadata),
	)

	return nil
}

_vk_emit_execute_draw_indirect :: proc(
	metadata: ^_Command_Buffer_Metadata,
	command: _Command_Execute_Indirect,
	icp_metadata: ^_Indirect_Command_Pool_Metadata,
	ic_metadata: ^_Indirect_Command_Metadata,
) -> Result {
	assert(ic_metadata.type == .Draw || ic_metadata.type == .Draw_Count)

	pipeline := ic_metadata.draw.render_pipeline
	arguments := ic_metadata.draw.arguments
	arguments_ptr := cast(uintptr)arguments

	_vk_use_resource_set(metadata, command.resource_set) or_return
	_vk_use_depth_stencil_state(metadata, command.depth_stencil_state) or_return
	_vk_use_render_pipeline(metadata, pipeline) or_return
	_vk_use_scissor(metadata, command.scissor) or_return
	vk.CmdPushConstants(metadata.vk.command_buffer, _vk_render_pipeline_layout, { .VERTEX, .FRAGMENT }, 0, size_of(uintptr), &arguments_ptr)

	if ic_metadata.type == .Draw_Count || ic_metadata.type == .Draw_Indexed_Count {
		count_buffer := cast(uintptr)ic_metadata.draw_count.count
		count_info, count_info_res := _address_info_of(cast(rawptr)count_buffer)
		_check_internal_emission_result(count_info_res) or_return
		count_metadata, count_metadata_res := _metadata_of(count_info.buffer)
		_check_internal_emission_result(count_metadata_res) or_return
		vk.CmdDrawIndirectCount(
			metadata.vk.command_buffer, icp_metadata.vk.buffer,
			cast(vk.DeviceSize)_vk_draw_icp_draw_command_offset(icp_metadata, ic_metadata),
			count_metadata.vk.buffer, cast(vk.DeviceSize)count_info.offset,
			cast(u32)icp_metadata.max_call_count_per_command,
			cast(u32)_VK_INDIRECT_COMMAND_STRIDE,
		)
	} else {
		vk.CmdDrawIndirect(
			metadata.vk.command_buffer,
			icp_metadata.vk.buffer,
			cast(vk.DeviceSize)_vk_draw_icp_draw_command_offset(icp_metadata, ic_metadata),
			cast(u32)ic_metadata.draw.count,
			cast(u32)_VK_INDIRECT_COMMAND_STRIDE,
		)
	}
	return nil
}

_vk_emit_execute_draw_indexed_indirect :: proc(
	metadata: ^_Command_Buffer_Metadata,
	command: _Command_Execute_Indirect,
	icp_metadata: ^_Indirect_Command_Pool_Metadata,
	ic_metadata: ^_Indirect_Command_Metadata,
) -> Result {
	assert(ic_metadata.type == .Draw_Indexed || ic_metadata.type == .Draw_Indexed_Count)

	pipeline := ic_metadata.draw_indexed.render_pipeline
	arguments := ic_metadata.draw_indexed.arguments
	arguments_ptr := cast(uintptr)arguments

	_vk_use_resource_set(metadata, command.resource_set) or_return
	_vk_use_depth_stencil_state(metadata, command.depth_stencil_state) or_return
	_vk_use_render_pipeline(metadata, pipeline) or_return
	_vk_use_scissor(metadata, command.scissor) or_return
	vk.CmdPushConstants(metadata.vk.command_buffer, _vk_render_pipeline_layout, { .VERTEX, .FRAGMENT }, 0, size_of(uintptr), &arguments_ptr)

	indices_info, indices_info_res := _address_info_of(ic_metadata.draw_indexed.indices)
	_check_internal_emission_result(indices_info_res) or_return
	indices_metadata, indices_res := _metadata_of(indices_info.buffer)
	_check_internal_emission_result(indices_res) or_return
	vk.CmdBindIndexBuffer(
		metadata.vk.command_buffer,
		indices_metadata.vk.buffer,
		cast(vk.DeviceSize)indices_info.offset,
		_vk_INDEX_TYPE_TO_VK[ic_metadata.draw_indexed.index_type],
	)

	if ic_metadata.type == .Draw_Indexed_Count {
		count_info, count_info_res := _address_info_of(ic_metadata.draw_indexed_count.count)
		_check_internal_emission_result(count_info_res) or_return
		count_metadata, count_metadata_res := _metadata_of(count_info.buffer)
		_check_internal_emission_result(count_metadata_res) or_return
		vk.CmdDrawIndexedIndirectCount(metadata.vk.command_buffer, icp_metadata.vk.buffer,
			cast(vk.DeviceSize)_vk_draw_icp_draw_command_offset(icp_metadata, ic_metadata),
			count_metadata.vk.buffer, cast(vk.DeviceSize)count_info.offset,
			cast(u32)icp_metadata.max_call_count_per_command,
			cast(u32)_VK_INDIRECT_COMMAND_STRIDE)
	} else {
		vk.CmdDrawIndexedIndirect(metadata.vk.command_buffer, icp_metadata.vk.buffer,
			cast(vk.DeviceSize)_vk_draw_icp_draw_command_offset(icp_metadata, ic_metadata),
			cast(u32)ic_metadata.draw_indexed.count, cast(u32)_VK_INDIRECT_COMMAND_STRIDE)
	}

	return nil
}

_vk_icp_scratch_alloc_slot :: proc(metadata: ^_Indirect_Command_Pool_Metadata) -> int {
	for {
		old := sync.atomic_load(&metadata.vk.index)
		next := (old + 1) % metadata.command_count
		_, exchanged := sync.atomic_compare_exchange_weak(&metadata.vk.index, old, next)
		if exchanged {
			return old
		}
	}
}

// Offset of a converted dispatch command in a dispatch pool.
_vk_dispatch_icp_indirect_command_offset :: proc(metadata: ^_Indirect_Command_Metadata) -> uintptr {
	return cast(uintptr)metadata.vk.slot * size_of(vk.DispatchIndirectCommand)
}

// Offset of the indirect dispatch command used to encode a draw pool command.
_vk_draw_icp_indirect_dispatch_offset :: proc(
	pool: ^_Indirect_Command_Pool_Metadata,
	metadata: ^_Indirect_Command_Metadata,
) -> uintptr {
	return cast(uintptr)metadata.vk.slot * size_of(vk.DispatchIndirectCommand)
}

// Offset of the first draw command in a draw pool.
_vk_draw_icp_draw_commands_offset :: proc(command_count: int) -> uintptr {
	return cast(uintptr)command_count * size_of(vk.DispatchIndirectCommand)
}

// Offset of the fixed draw-command slot assigned to an indirect command.
_vk_draw_icp_draw_command_offset :: proc(
	pool: ^_Indirect_Command_Pool_Metadata,
	metadata: ^_Indirect_Command_Metadata,
) -> uintptr {
	return _vk_draw_icp_draw_commands_offset(pool.command_count) +
		cast(uintptr)(metadata.vk.slot * pool.max_call_count_per_command * _VK_INDIRECT_COMMAND_STRIDE)
}
