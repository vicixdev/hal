package gfx

import vk "vendor:vulkan"

vk_Command_Buffer_Metadata :: struct {
	command_buffer:	vk.CommandBuffer,
}

vk_setup_command_buffer :: proc(metadata: ^_Command_Buffer_Metadata, queue_metadata: ^_Queue_Metadata) -> Result {
	allocate_info := vk.CommandBufferAllocateInfo {
		sType			= .COMMAND_BUFFER_ALLOCATE_INFO,
		commandPool		= queue_metadata.vk.command_pool,
		level			= .PRIMARY,
		commandBufferCount	= 1,
	}
	vk_call(vk.AllocateCommandBuffers(vk_device, &allocate_info, &metadata.vk.command_buffer)) or_return

	return nil
}

vk_begin_command_encoding :: proc(metadata: ^_Command_Buffer_Metadata, queue_metadata: ^_Queue_Metadata) -> Result {
	begin_info := vk.CommandBufferBeginInfo {
		sType	= .COMMAND_BUFFER_BEGIN_INFO,
		flags	= { .ONE_TIME_SUBMIT },
	}
	vk_call(vk.BeginCommandBuffer(metadata.vk.command_buffer, &begin_info)) or_return

	return nil
}

vk_use_resources :: proc(
	metadata: ^_Command_Buffer_Metadata,
	resource_set_metadata: ^_Resource_Set_Metadata,
) -> Result {

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

vk_mem_copy :: proc(
	metadata:		^_Command_Buffer_Metadata,
	destination_metadata:	^_Buffer_Metadata,
	destination_offset:	uintptr,
	source_metadata:	^_Buffer_Metadata,
	source_offset:		uintptr,
	length:			int,
) -> Result {
	
	region := vk.BufferCopy {
		srcOffset	= cast(vk.DeviceSize)source_offset,
		dstOffset	= cast(vk.DeviceSize)destination_offset,
		size		= cast(vk.DeviceSize)length,
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

vk_dispatch :: proc(
	metadata:		^_Command_Buffer_Metadata,
	pipeline_metadata:	^_Pipeline_Metadata,
	argument:		[]byte,
	group_count:		[3]int,
) -> Result {

	@(static)
	push_constant_buffer: [64]byte

	push_constant_buffer = {}
	copy(push_constant_buffer[:], argument)

	vk.CmdPushConstants(
		metadata.vk.command_buffer,
		vk_compute_pipeline_layout,
		{ .COMPUTE },
		0,
		64,
		raw_data(push_constant_buffer[:]),
	)
	vk.CmdBindPipeline(metadata.vk.command_buffer, .COMPUTE, pipeline_metadata.vk.pipeline)
	vk.CmdDispatch(metadata.vk.command_buffer, cast(u32)group_count.x, cast(u32)group_count.y, cast(u32)group_count.z)

	return nil
}

vk_barrier :: proc(metadata: ^_Command_Buffer_Metadata, after: Stages, before: Stages) -> Result {
	memory_barrier := vk.MemoryBarrier2 {
		sType			= .MEMORY_BARRIER_2,
		srcStageMask		= vk_stages_to_vk(after),
		srcAccessMask		= { .MEMORY_WRITE, .MEMORY_READ },
		dstStageMask		= vk_stages_to_vk(before),
		dstAccessMask		= { .MEMORY_WRITE, .MEMORY_READ },
	}
	barrier_info := vk.DependencyInfo {
		sType			= .DEPENDENCY_INFO,
		memoryBarrierCount	= 1,
		pMemoryBarriers		= &memory_barrier,
	}
	vk.CmdPipelineBarrier2KHR(metadata.vk.command_buffer, &barrier_info)
	
	return nil
}

vk_signal_fence :: proc(
	metadata:	^_Command_Buffer_Metadata,
	queue_metadata:	^_Queue_Metadata,
	fence_metadata: ^_Fence_Metadata,
	after:		Stages,
	value:		int,
) -> Result {
	
	vk_call(vk.EndCommandBuffer(metadata.vk.command_buffer)) or_return

	semaphore_submit_info := vk.SemaphoreSubmitInfo {
		sType		= .SEMAPHORE_SUBMIT_INFO,
		semaphore	= fence_metadata.vk.semaphore,
		value		= cast(u64)value,
		stageMask	= vk_stages_to_vk(after),
	}
	command_buffer_submit_info := vk.CommandBufferSubmitInfo {
		sType		= .COMMAND_BUFFER_SUBMIT_INFO,
		commandBuffer	= metadata.vk.command_buffer,
	}
	submit_info := vk.SubmitInfo2 {
		sType				= .SUBMIT_INFO_2,
		commandBufferInfoCount		= 1,
		pCommandBufferInfos		= &command_buffer_submit_info,
		signalSemaphoreInfoCount	= 1,
		pSignalSemaphoreInfos		= &semaphore_submit_info,
	}
	vk_call(vk.QueueSubmit2KHR(queue_metadata.vk.queue, 1, &submit_info, {})) or_return

	begin_info := vk.CommandBufferBeginInfo {
		sType	= .COMMAND_BUFFER_BEGIN_INFO,
		flags	= { .ONE_TIME_SUBMIT },
	}
	vk_call(vk.BeginCommandBuffer(metadata.vk.command_buffer, &begin_info)) or_return

	return nil
}

vk_wait_fence :: proc(
	metadata: 	^_Command_Buffer_Metadata,
	queue_metadata: ^_Queue_Metadata,
	fence_metadata: ^_Fence_Metadata,
	before:		Stages,
	value:		int,
) -> Result {
	vk_call(vk.EndCommandBuffer(metadata.vk.command_buffer)) or_return

	semaphore_wait_info := vk.SemaphoreSubmitInfo {
		sType		= .SEMAPHORE_SUBMIT_INFO,
		semaphore	= fence_metadata.vk.semaphore,
		value		= cast(u64)value,
		stageMask	= vk_stages_to_vk(before),
	}
	command_buffer_submit_info := vk.CommandBufferSubmitInfo {
		sType		= .COMMAND_BUFFER_SUBMIT_INFO,
		commandBuffer	= metadata.vk.command_buffer,
	}
	submit_info := vk.SubmitInfo2 {
		sType				= .SUBMIT_INFO_2,
		commandBufferInfoCount		= 1,
		pCommandBufferInfos		= &command_buffer_submit_info,
		waitSemaphoreInfoCount		= 1,
		pWaitSemaphoreInfos		= &semaphore_wait_info,
	}
	vk_call(vk.QueueSubmit2KHR(queue_metadata.vk.queue, 1, &submit_info, {})) or_return

	begin_info := vk.CommandBufferBeginInfo {
		sType	= .COMMAND_BUFFER_BEGIN_INFO,
		flags	= { .ONE_TIME_SUBMIT },
	}
	vk_call(vk.BeginCommandBuffer(metadata.vk.command_buffer, &begin_info)) or_return

	return nil
}

vk_submit :: proc(metadata: ^_Command_Buffer_Metadata, queue_metadata: ^_Queue_Metadata) -> Result {
	vk_call(vk.EndCommandBuffer(metadata.vk.command_buffer)) or_return

	command_buffer_submit_info := vk.CommandBufferSubmitInfo {
		sType		= .COMMAND_BUFFER_SUBMIT_INFO,
		commandBuffer	= metadata.vk.command_buffer,
	}
	submit_info := vk.SubmitInfo2 {
		sType			= .SUBMIT_INFO_2,
		commandBufferInfoCount	= 1,
		pCommandBufferInfos	= &command_buffer_submit_info,
	}
	vk_call(vk.QueueSubmit2KHR(queue_metadata.vk.queue, 1, &submit_info, {})) or_return

	return nil
}

vk_submit_and_signal :: proc(
	metadata:		^_Command_Buffer_Metadata,
	queue_metadata:		^_Queue_Metadata,
	semaphore_metadata:	^_Semaphore_Metadata,
	value: int,
) -> Result {
	vk_call(vk.EndCommandBuffer(metadata.vk.command_buffer)) or_return

	signal_info := vk.SemaphoreSubmitInfo {
		sType		= .SEMAPHORE_SUBMIT_INFO,
		semaphore	= semaphore_metadata.vk.semaphore,
		value		= cast(u64)value,
		stageMask	= { .ALL_COMMANDS },
	}
	command_buffer_submit_info := vk.CommandBufferSubmitInfo {
		sType		= .COMMAND_BUFFER_SUBMIT_INFO,
		commandBuffer	= metadata.vk.command_buffer,
	}
	submit_info := vk.SubmitInfo2 {
		sType				= .SUBMIT_INFO_2,
		commandBufferInfoCount		= 1,
		pCommandBufferInfos		= &command_buffer_submit_info,
		signalSemaphoreInfoCount	= 1,
		pSignalSemaphoreInfos		= &signal_info,
	}
	vk_call(vk.QueueSubmit2KHR(queue_metadata.vk.queue, 1, &submit_info, {})) or_return

	return nil
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

