package gfx

import vk "vendor:vulkan"

vk_Fence_Signal :: struct {
	fence:	Fence,
	value:	int,
	stages:	Stages,
}

// GfxToVk conversion notes:
//	- memory barriers are analogous to vk.PipelineBarrier
//	- signals and waits imply a command buffer flush. 

vk_Command_Buffer_Metadata :: struct {
	command_buffer:			vk.CommandBuffer,
	command_buffer_valid:		bool,

	bound_resource_set:		Resource_Set,

	is_first_command_buffer:	bool,
	pending_waits:			[]Fence,

	semaphore:			vk.Semaphore,
	semaphore_value:		u64,
}

vk_setup_command_buffer :: proc(metadata: ^_Command_Buffer_Metadata, queue_metadata: ^_Queue_Metadata) -> Result {
	semaphore_type_info := vk.SemaphoreTypeCreateInfo {
		sType		= .SEMAPHORE_TYPE_CREATE_INFO,
		semaphoreType	= .TIMELINE,
		initialValue	= 0,
	}
	semaphore_info := vk.SemaphoreCreateInfo {
		sType	= .SEMAPHORE_CREATE_INFO,
		pNext	= &semaphore_type_info,
	}
	vk_call(vk.CreateSemaphore(vk_device, &semaphore_info, nil, &metadata.vk.semaphore)) or_return

	return nil
}

vk_destroy_command_buffer :: proc(metadata: ^_Command_Buffer_Metadata, queue_metadata: ^_Queue_Metadata) {
	vk.DestroySemaphore(vk_device, metadata.vk.semaphore, nil)
}

vk_emit_mem_copy :: proc(
	metadata:	^_Command_Buffer_Metadata,
	queue_metadata:	^_Queue_Metadata,
	command:	_Command_Mem_Copy,
) -> Result {
	
	source_metadata, source_res := _metadata_of(command.source)
	_check_internal_emission_result(source_res) or_return

	destination_metadata, destination_res := _metadata_of(command.destination)
	_check_internal_emission_result(destination_res) or_return

	source_offset := _offset_from_base(command.source, source_metadata)
	destination_offset := _offset_from_base(command.destination, destination_metadata)

	vk_ensure_command_buffer_valid(metadata, queue_metadata) or_return

	region := vk.BufferCopy {
		srcOffset	= cast(vk.DeviceSize)source_offset,
		dstOffset	= cast(vk.DeviceSize)destination_offset,
		size		= cast(vk.DeviceSize)command.size,
	}
	vk.CmdCopyBuffer(
		metadata.vk.command_buffer,
		source_metadata.vk.buffer,
		destination_metadata.vk.buffer,
		1,
		&region,
	)

	return nil
}

vk_use_resource_set :: proc(
	metadata:	^_Command_Buffer_Metadata,
	resource_set:	Resource_Set,
) -> Result {

	if resource_set == metadata.vk.bound_resource_set {
		return nil
	}

	resource_set_metadata, resource_set_res := _metadata_of(resource_set)
	_check_internal_emission_result(resource_set_res) or_return

	vk.CmdBindDescriptorSets(
		metadata.vk.command_buffer,
		.COMPUTE,
		vk_compute_pipeline_layout,
		0,
		1,
		&resource_set_metadata.vk.descriptor_set,
		0,
		nil,
	)
	vk.CmdBindDescriptorSets(
		metadata.vk.command_buffer,
		.GRAPHICS,
		vk_compute_pipeline_layout,
		0,
		1,
		&resource_set_metadata.vk.descriptor_set,
		0,
		nil,
	)

	return nil
}

vk_emit_dispatch :: proc(
	metadata:	^_Command_Buffer_Metadata,
	queue_metadata:	^_Queue_Metadata,
	command:	_Command_Dispatch,
) -> Result {
	
	push_constant_buffer: [64]byte

	pipeline_metadata, pipeline_res := _metadata_of(command.pipeline)
	_check_internal_emission_result(pipeline_res) or_return

	push_constant_buffer = {}
	copy(push_constant_buffer[:], command.argument)

	vk_ensure_command_buffer_valid(metadata, queue_metadata) or_return

	vk_use_resource_set(metadata, command.resource_set)
	vk.CmdPushConstants(
		metadata.vk.command_buffer,
		vk_compute_pipeline_layout,
		{ .COMPUTE },
		0,
		64,
		raw_data(push_constant_buffer[:]),
	)
	vk.CmdBindPipeline(metadata.vk.command_buffer, .COMPUTE, pipeline_metadata.vk.pipeline)
	vk.CmdDispatch(
		metadata.vk.command_buffer,
		cast(u32)command.group_count.x,
		cast(u32)command.group_count.y,
		cast(u32)command.group_count.z,
	)

	return nil
}

vk_emit_barrier :: proc(
	metadata:	^_Command_Buffer_Metadata,
	queue_metadata:	^_Queue_Metadata,
	command:	_Command_Barrier,
) -> Result {

	vk_ensure_command_buffer_valid(metadata, queue_metadata) or_return

	memory_barrier := vk.MemoryBarrier2 {
		sType			= .MEMORY_BARRIER_2,
		srcStageMask		= vk_stages_to_vk(command.after),
		srcAccessMask		= { .MEMORY_WRITE, .MEMORY_READ },
		dstStageMask		= vk_stages_to_vk(command.before),
		dstAccessMask		= { .MEMORY_WRITE, .MEMORY_READ },
	}
	dependency_info := vk.DependencyInfo {
		sType			= .DEPENDENCY_INFO,
		memoryBarrierCount	= 1,
		pMemoryBarriers		= &memory_barrier,
	}
	vk.CmdPipelineBarrier2KHR(metadata.vk.command_buffer, &dependency_info)
	
	return nil
}

vk_emit_signal :: proc(
	metadata:	^_Command_Buffer_Metadata,
	queue_metadata:	^_Queue_Metadata,
	command:	_Command_Signal,
) -> Result {
	
	vk.EndCommandBuffer(metadata.vk.command_buffer)
	metadata.vk.command_buffer_valid = false

	waits := vk_prepare_wait_semaphore_submit_infos(metadata) or_return
	signals := vk_prepare_signal_semaphore_submit_infos(metadata, command.signals) or_return

	command_buffer_info := vk.CommandBufferSubmitInfo {
		sType		= .COMMAND_BUFFER_SUBMIT_INFO,
		commandBuffer	= metadata.vk.command_buffer,
	}
	submit_info := vk.SubmitInfo2 {
		sType				= .SUBMIT_INFO_2,
		waitSemaphoreInfoCount		= cast(u32)len(waits),
		pWaitSemaphoreInfos		= raw_data(waits),
		signalSemaphoreInfoCount	= cast(u32)len(signals),
		pSignalSemaphoreInfos		= raw_data(signals),
		commandBufferInfoCount		= 1,
		pCommandBufferInfos		= &command_buffer_info,
	}
	vk_call(vk.QueueSubmit2KHR(queue_metadata.vk.queue, 1, &submit_info, 0)) or_return

	metadata.vk.is_first_command_buffer = false
	metadata.vk.pending_waits = {}
	metadata.vk.semaphore_value += 1

	return nil
}

vk_emit_wait :: proc(
	metadata:	^_Command_Buffer_Metadata,
	queue_metadata:	^_Queue_Metadata,
	command:	_Command_Wait,
) -> Result {

	metadata.vk.pending_waits = command.waits

	return nil
}

vk_emit_commands :: proc(
	metadata: ^_Command_Buffer_Metadata,
	queue_metadata: ^_Queue_Metadata,
) -> (submit_info: vk.SubmitInfo2, res: Result) {

	metadata.vk.bound_resource_set = {}
	metadata.vk.command_buffer_valid = false
	metadata.vk.is_first_command_buffer = true
	metadata.vk.pending_waits = {}

	vk_ensure_command_buffer_valid(metadata, queue_metadata)

	for command in metadata.commands {
		switch v in command {
		case _Command_Mem_Copy:		vk_emit_mem_copy(metadata, queue_metadata, v) or_return
		case _Command_Dispatch:		vk_emit_dispatch(metadata, queue_metadata, v) or_return
		case _Command_Barrier:		vk_emit_barrier(metadata, queue_metadata, v) or_return
		case _Command_Signal:		vk_emit_signal(metadata, queue_metadata, v) or_return
		case _Command_Wait:		vk_emit_wait(metadata, queue_metadata, v) or_return
		}
	}

	vk_ensure_command_buffer_valid(metadata, queue_metadata)
	vk_call(vk.EndCommandBuffer(metadata.vk.command_buffer)) or_return

	command_buffer_info := new(vk.CommandBufferSubmitInfo, metadata.allocator) or_return
	waits := vk_prepare_wait_semaphore_submit_infos(metadata) or_return
	signals := vk_prepare_signal_semaphore_submit_infos(metadata, {}) or_return

	command_buffer_info^ = vk.CommandBufferSubmitInfo {
		sType		= .COMMAND_BUFFER_SUBMIT_INFO,
		commandBuffer	= metadata.vk.command_buffer,
	}
	submit_info = vk.SubmitInfo2 {
		sType				= .SUBMIT_INFO_2,
		commandBufferInfoCount		= 1,
		pCommandBufferInfos		= command_buffer_info,
		waitSemaphoreInfoCount		= cast(u32)len(waits),
		pWaitSemaphoreInfos		= raw_data(waits),
		signalSemaphoreInfoCount	= cast(u32)len(signals),
		pSignalSemaphoreInfos		= raw_data(signals),
	}

	metadata.vk.semaphore_value += 1
	metadata.vk.is_first_command_buffer = false
	metadata.vk.pending_waits = {}
	
	return submit_info, nil
}

vk_submit :: proc(
	queue_metadata: ^_Queue_Metadata,
	command_buffers: []Command_Buffer,
	signals: []Semaphore_Signal,
) -> Result {

	fence := vk_begin_command_group(&queue_metadata.vk.command_pool) or_return
	defer vk_end_command_group(&queue_metadata.vk.command_pool)

	submit_infos := make([]vk.SubmitInfo2, len(command_buffers), _temp_allocator) or_return
	for command_buffer, i in command_buffers {
		metadata, metadata_res := _metadata_of(command_buffer)
		_check_internal_emission_result(metadata_res) or_return

		submit_infos[i] = vk_emit_commands(metadata, queue_metadata) or_return
	}

	vk_call(
		vk.QueueSubmit2KHR(queue_metadata.vk.queue, cast(u32)len(submit_infos), raw_data(submit_infos), fence),
	) or_return


	wait_infos := make([]vk.SemaphoreSubmitInfo, len(command_buffers), _temp_allocator) or_return
	for command_buffer, i in command_buffers {
		metadata, metadata_res := _metadata_of(command_buffer)
		_check_internal_emission_result(metadata_res) or_return

		wait_infos[i] = vk.SemaphoreSubmitInfo {
			sType		= .SEMAPHORE_SUBMIT_INFO,
			semaphore	= metadata.vk.semaphore,
			value		= metadata.vk.semaphore_value,
			stageMask	= { .ALL_COMMANDS },
		}
	}

	signal_infos := make([]vk.SemaphoreSubmitInfo, len(signals), _temp_allocator) or_return
	for signal, i in signals {
		metadata, metadata_res := _metadata_of(signal.semaphore)
		_check_internal_emission_result(metadata_res) or_return

		signal_infos[i] = vk.SemaphoreSubmitInfo {
			sType		= .SEMAPHORE_SUBMIT_INFO,
			semaphore	= metadata.vk.semaphore,
			value		= cast(u64)signal.value,
			stageMask	= { .ALL_COMMANDS },
		}
	}

	submit_info := vk.SubmitInfo2 {
		sType				= .SUBMIT_INFO_2,
		waitSemaphoreInfoCount		= cast(u32)len(wait_infos),
		pWaitSemaphoreInfos		= raw_data(wait_infos),
		signalSemaphoreInfoCount	= cast(u32)len(signal_infos),
		pSignalSemaphoreInfos		= raw_data(signal_infos),
	}
	vk_call(vk.QueueSubmit2KHR(queue_metadata.vk.queue, 1, &submit_info, 0)) or_return
	
	return nil
}

vk_ensure_command_buffer_valid :: proc(
	metadata:	^_Command_Buffer_Metadata,
	queue_metadata:	^_Queue_Metadata,
) -> Result {
	if metadata.vk.command_buffer_valid {
		return nil
	}

	metadata.vk.command_buffer = vk_acquire_command_buffer_from(&queue_metadata.vk.command_pool) or_return

	begin_info := vk.CommandBufferBeginInfo {
		sType	= .COMMAND_BUFFER_BEGIN_INFO,
		flags	= { .ONE_TIME_SUBMIT },
	}
	vk_call(vk.BeginCommandBuffer(metadata.vk.command_buffer, &begin_info)) or_return

	metadata.vk.command_buffer_valid = true

	return nil
}

vk_prepare_wait_semaphore_submit_infos :: proc(
	metadata: ^_Command_Buffer_Metadata,
) -> (infos: []vk.SemaphoreSubmitInfo, res: Result) {

	wait_count := len(metadata.vk.pending_waits)
	if metadata.vk.is_first_command_buffer {
		wait_count += len(metadata.semaphore_waits)
	} else {
		wait_count += 1
		
	}

	waits := make([]vk.SemaphoreSubmitInfo, wait_count, metadata.allocator) or_return
	for fence, i in metadata.vk.pending_waits {
		fence_metadata, fence_res := _metadata_of(fence)
		_check_internal_emission_result(fence_res) or_return

		waits[i] = vk.SemaphoreSubmitInfo {
			sType		= .SEMAPHORE_SUBMIT_INFO,
			semaphore	= fence_metadata.vk.semaphore,
			value		= fence_metadata.vk.last_signaled_value,
			stageMask	= { .ALL_COMMANDS },
		}
	}

	if metadata.vk.is_first_command_buffer {
		base := len(metadata.vk.pending_waits)

		for wait, i in metadata.semaphore_waits {
			semaphore_metadata, semaphore_res := _metadata_of(wait.semaphore)
			_check_internal_emission_result(semaphore_res) or_return

			waits[base + i] = vk.SemaphoreSubmitInfo {
				sType		= .SEMAPHORE_SUBMIT_INFO,
				semaphore	= semaphore_metadata.vk.semaphore,
				value		= cast(u64)wait.value,
				stageMask	= { .ALL_COMMANDS },
			}
		}
	} else {
		waits[len(waits)-1] = vk.SemaphoreSubmitInfo {
			sType		= .SEMAPHORE_SUBMIT_INFO,
			semaphore	= metadata.vk.semaphore,
			value		= metadata.vk.semaphore_value,
			stageMask	= { .ALL_COMMANDS },
		}
	}

	return waits, nil
}

vk_prepare_signal_semaphore_submit_infos :: proc(
	metadata:	^_Command_Buffer_Metadata,
	fences:		[]Fence,
) -> (infos: []vk.SemaphoreSubmitInfo, res: Result) {
	
	signals := make([]vk.SemaphoreSubmitInfo, len(fences) + 1, metadata.allocator) or_return

	signals[len(signals) - 1] = vk.SemaphoreSubmitInfo {
		sType		= .SEMAPHORE_SUBMIT_INFO,
		semaphore	= metadata.vk.semaphore,
		value		= metadata.vk.semaphore_value + 1,
		stageMask	= { .ALL_COMMANDS },
	}

	for fence, i in fences {
		fence_metadata, fence_res := _metadata_of(fence)
		_check_internal_emission_result(fence_res) or_return

		fence_metadata.vk.last_signaled_value += 1
		signals[i] = vk.SemaphoreSubmitInfo {
			sType		= .SEMAPHORE_SUBMIT_INFO,
			semaphore	= fence_metadata.vk.semaphore,
			value		= fence_metadata.vk.last_signaled_value,
			stageMask	= { .ALL_COMMANDS },
		}
	}

	return signals, nil
}

vk_stages_to_vk :: proc(stages: Stages) -> (flags: vk.PipelineStageFlags2) {
	for stage in stages {
		flags += vk_STAGE_TO_VK[stage]
	}

	return
}

vk_STAGE_TO_VK := [Stage]vk.PipelineStageFlags2 {
	.Transfer	= { .TRANSFER },
	.Compute	= { .COMPUTE_SHADER },
	.Raster		= { .COLOR_ATTACHMENT_OUTPUT },
}

