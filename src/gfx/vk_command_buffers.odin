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

	pending_render_pass_waits:	[]Render_Pass_Wait,
	pending_render_pass_signals:	[]Render_Pass_Signal,

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

vk_emit_copy_texture_to_texture :: proc(
	metadata:	^_Command_Buffer_Metadata,
	queue_metadata:	^_Queue_Metadata,
	command:	_Command_Copy_Texture_To_Texture,
) -> Result {
	source_metadata, source_res := _metadata_of(command.source)
	_check_internal_emission_result(source_res) or_return

	destination_metadata, destination_res := _metadata_of(command.destination)
	_check_internal_emission_result(destination_res) or_return

	vk_ensure_command_buffer_valid(metadata, queue_metadata) or_return

	image_copy := vk.ImageCopy {
		srcSubresource	= vk.ImageSubresourceLayers {
			aspectMask	= vk_PIXEL_FORMAT_TO_VK_ASPECT_MASK[source_metadata.format],
			mipLevel	= cast(u32)command.source_region.mip,
			baseArrayLayer	= cast(u32)command.source_region.base_layer,
			layerCount	= cast(u32)command.source_region.layer_count,
		},
		srcOffset	= vk_origin_to_vk_offset(command.source_region.origin),
		dstSubresource	= vk.ImageSubresourceLayers {
			aspectMask	= vk_PIXEL_FORMAT_TO_VK_ASPECT_MASK[destination_metadata.format],
			mipLevel	= cast(u32)command.destination_region.mip,
			baseArrayLayer	= cast(u32)command.destination_region.base_layer,
			layerCount	= cast(u32)command.destination_region.layer_count,
		},
		dstOffset	= vk_origin_to_vk_offset(command.destination_region.origin),
		extent		= vk_size_to_vk_extent(command.source_region.size),
	}
	vk.CmdCopyImage(
		metadata.vk.command_buffer,
		source_metadata.vk.image,
		.GENERAL,
		destination_metadata.vk.image,
		.GENERAL,
		1,
		&image_copy,
	)

	return nil
}

vk_emit_copy_buffer_to_texture :: proc(
	metadata:	^_Command_Buffer_Metadata,
	queue_metadata:	^_Queue_Metadata,
	command:	_Command_Copy_Buffer_To_Texture,
) -> Result {

	source_metadata, source_res := _metadata_of(command.source)
	_check_internal_emission_result(source_res) or_return
	source_offset := _offset_from_base(command.source, source_metadata)

	texture_metadata, texture_res := _metadata_of(command.texture)
	_check_internal_emission_result(texture_res) or_return

	vk_ensure_command_buffer_valid(metadata, queue_metadata) or_return
	
	region := vk.BufferImageCopy {
		bufferOffset		= cast(vk.DeviceSize)source_offset,
		bufferRowLength		= cast(u32)command.region.size.x,
		bufferImageHeight	= cast(u32)command.region.size.y,
		imageOffset		= vk_origin_to_vk_offset(command.region.origin),
		imageExtent		= vk_size_to_vk_extent(command.region.size),
		imageSubresource	= vk.ImageSubresourceLayers {
			aspectMask	= vk_PIXEL_FORMAT_TO_VK_ASPECT_MASK[texture_metadata.format],
			mipLevel	= cast(u32)command.region.mip,
			baseArrayLayer	= cast(u32)command.region.base_layer,
			layerCount	= cast(u32)command.region.layer_count,
		},
	}
	vk.CmdCopyBufferToImage(
		metadata.vk.command_buffer,
		source_metadata.vk.buffer,
		texture_metadata.vk.image,
		.GENERAL,
		1,
		&region,
	)
	
	return nil
}

vk_emit_copy_texture_to_buffer :: proc(
	metadata:	^_Command_Buffer_Metadata,
	queue_metadata:	^_Queue_Metadata,
	command:	_Command_Copy_Texture_To_Buffer,
) -> Result {

	destination_metadata, destination_res := _metadata_of(command.destination)
	_check_internal_emission_result(destination_res) or_return
	destination_offset := _offset_from_base(command.destination, destination_metadata)

	texture_metadata, texture_res := _metadata_of(command.texture)
	_check_internal_emission_result(texture_res) or_return

	vk_ensure_command_buffer_valid(metadata, queue_metadata) or_return
	
	region := vk.BufferImageCopy {
		bufferOffset		= cast(vk.DeviceSize)destination_offset,
		bufferRowLength		= cast(u32)command.region.size.x,
		bufferImageHeight	= cast(u32)command.region.size.y,
		imageOffset		= vk_origin_to_vk_offset(command.region.origin),
		imageExtent		= vk_size_to_vk_extent(command.region.size),
		imageSubresource	= vk.ImageSubresourceLayers {
			aspectMask	= vk_PIXEL_FORMAT_TO_VK_ASPECT_MASK[texture_metadata.format],
			mipLevel	= cast(u32)command.region.mip,
			baseArrayLayer	= cast(u32)command.region.base_layer,
			layerCount	= cast(u32)command.region.layer_count,
		},
	}
	vk.CmdCopyImageToBuffer(
		metadata.vk.command_buffer,
		texture_metadata.vk.image,
		.GENERAL,
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
		vk_render_pipeline_layout,
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
	metadata.vk.pending_render_pass_signals = {}
	metadata.vk.pending_render_pass_waits = {}
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

vk_emit_begin_render_pass :: proc(
	metadata:	^_Command_Buffer_Metadata,
	queue_metadata:	^_Queue_Metadata,
	command:	_Command_Begin_Render_Pass,
) -> Result {

	vk_ensure_command_buffer_valid(metadata, queue_metadata) or_return

	if metadata.vk.pending_render_pass_signals != nil {
		vk.EndCommandBuffer(metadata.vk.command_buffer)
		metadata.vk.command_buffer_valid = false

		waits := vk_prepare_wait_semaphore_submit_infos(metadata) or_return
		signals := vk_prepare_signal_semaphore_submit_infos(metadata, {}) or_return

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
		metadata.vk.pending_render_pass_signals = {}
		metadata.vk.pending_render_pass_waits = {}
		metadata.vk.semaphore_value += 1

		vk_ensure_command_buffer_valid(metadata, queue_metadata) or_return
	}

	render_area: [2]int

	color_attachment_infos := make(
		[]vk.RenderingAttachmentInfo,
		len(command.color_attachments),
		metadata.allocator,
	) or_return
	for attachment, i in command.color_attachments {
		view_metadata, view_res := _metadata_of(attachment.view)
		_check_internal_emission_result(view_res) or_return

		texture_metadata, texture_res := _metadata_of(view_metadata.texture)
		assert(texture_res == nil)

		// TODO: Figure out reductions
		color_attachment_infos[i] = {
			sType			= .RENDERING_ATTACHMENT_INFO,
			imageView		= view_metadata.vk.view,
			imageLayout		= .GENERAL,
			loadOp			= vk_LOAD_OPERATION_TO_VK[attachment.load_operation],
			storeOp			= vk_STORE_OPERATION_TO_VK[attachment.store_operation],
			clearValue		= {
				color	= {
					float32 = {
						cast(f32)attachment.clear_value.([4]f64).r,
						cast(f32)attachment.clear_value.([4]f64).g,
						cast(f32)attachment.clear_value.([4]f64).b,
						cast(f32)attachment.clear_value.([4]f64).a,
					},
				},
			},
		}

		render_area.x = max(render_area.x, texture_metadata.dimensions.x)
		render_area.y = max(render_area.y, texture_metadata.dimensions.y)
	}

	depth_attachment_info: ^vk.RenderingAttachmentInfo
	if attachment, has_depth_attachment := command.depth_attachment.?; has_depth_attachment {
		view_metadata, view_res := _metadata_of(attachment.view)
		_check_internal_emission_result(view_res) or_return

		texture_metadata, texture_res := _metadata_of(view_metadata.texture)
		assert(texture_res == nil)

		depth_attachment_info = &{
			sType			= .RENDERING_ATTACHMENT_INFO,
			imageView		= view_metadata.vk.view,
			imageLayout		= .GENERAL,
			loadOp			= vk_LOAD_OPERATION_TO_VK[attachment.load_operation],
			storeOp			= vk_STORE_OPERATION_TO_VK[attachment.store_operation],
			clearValue		= {
				depthStencil	= {
					depth	= cast(f32)attachment.clear_value.(f64),
				},
			},
		}

		render_area.x = max(render_area.x, texture_metadata.dimensions.x)
		render_area.y = max(render_area.y, texture_metadata.dimensions.y)
	}

	stencil_attachment_info: ^vk.RenderingAttachmentInfo
	if attachment, has_stencil_attachment := command.stencil_attachment.?; has_stencil_attachment {
		view_metadata, view_res := _metadata_of(attachment.view)
		_check_internal_emission_result(view_res) or_return

		texture_metadata, texture_res := _metadata_of(view_metadata.texture)
		assert(texture_res == nil)

		stencil_attachment_info = &{
			sType			= .RENDERING_ATTACHMENT_INFO,
			imageView		= view_metadata.vk.view,
			imageLayout		= .GENERAL,
			loadOp			= vk_LOAD_OPERATION_TO_VK[attachment.load_operation],
			storeOp			= vk_STORE_OPERATION_TO_VK[attachment.store_operation],
			clearValue		= {
				depthStencil	= {
					stencil	= attachment.clear_value.(u32),
				},
			},
		}

		render_area.x = max(render_area.x, texture_metadata.dimensions.x)
		render_area.y = max(render_area.y, texture_metadata.dimensions.y)
	}

	rendering_info := vk.RenderingInfo {
		sType			= .RENDERING_INFO,
		layerCount		= 1,
		renderArea		= {
			extent = { cast(u32)render_area.x, cast(u32)render_area.y },
		},
		colorAttachmentCount	= cast(u32)len(color_attachment_infos),
		pColorAttachments	= raw_data(color_attachment_infos),
		pDepthAttachment	= depth_attachment_info,
		pStencilAttachment	= stencil_attachment_info,
	}

	vk.CmdBeginRenderingKHR(metadata.vk.command_buffer, &rendering_info)

	viewport := vk.Viewport {
		width		= cast(f32)render_area.x,
		height		= cast(f32)render_area.y,
		minDepth	= 0.0,
		maxDepth	= 1.0,
	}
	vk.CmdSetViewport(metadata.vk.command_buffer, 0, 1, &viewport)

	scissor := vk.Rect2D {
		extent = { cast(u32)render_area.x, cast(u32)render_area.y },
	}
	vk.CmdSetScissor(metadata.vk.command_buffer, 0, 1, &scissor)

	metadata.vk.pending_render_pass_waits = command.waits
	metadata.vk.pending_render_pass_signals = command.signals

	return nil
}

vk_emit_end_render_pass :: proc(
	metadata:	^_Command_Buffer_Metadata,
	queue_metadata:	^_Queue_Metadata,
	command:	_Command_End_Render_Pass,
) -> Result {

	vk.CmdEndRenderingKHR(metadata.vk.command_buffer)

	return nil
}

vk_emit_draw :: proc(
	metadata:	^_Command_Buffer_Metadata,
	queue_metadata:	^_Queue_Metadata,
	command:	_Command_Draw,
) -> Result {

	push_constant_buffer: [64]byte

	pipeline_metadata, pipeline_res := _metadata_of(command.pipeline)
	_check_internal_emission_result(pipeline_res) or_return

	push_constant_buffer = {}
	copy(push_constant_buffer[:], command.argument)

	vk_ensure_command_buffer_valid(metadata, queue_metadata) or_return

	vk_use_resource_set(metadata, command.resource_set)
	vk.CmdSetDepthTestEnableEXT(metadata.vk.command_buffer, false)
	vk.CmdPushConstants(
		metadata.vk.command_buffer,
		vk_render_pipeline_layout,
		{ .VERTEX, .FRAGMENT },
		0,
		64,
		raw_data(push_constant_buffer[:]),
	)
	vk.CmdBindPipeline(metadata.vk.command_buffer, .GRAPHICS, pipeline_metadata.vk.pipeline)
	vk.CmdDraw(
		metadata.vk.command_buffer,
		cast(u32)command.vertex_count,
		cast(u32)command.instance_count,
		cast(u32)command.base_vertex,
		0,
	)

	return nil
}

vk_emit_draw_indexed :: proc(
	metadata:	^_Command_Buffer_Metadata,
	queue_metadata:	^_Queue_Metadata,
	command:	_Command_Draw_Indexed,
) -> Result {

	push_constant_buffer: [64]byte

	pipeline_metadata, pipeline_res := _metadata_of(command.pipeline)
	_check_internal_emission_result(pipeline_res) or_return

	indices_metadata, indices_res := _metadata_of(command.indices)
	_check_internal_emission_result(indices_res) or_return
	indices_offset := _offset_from_base(command.indices, indices_metadata)

	push_constant_buffer = {}
	copy(push_constant_buffer[:], command.argument)

	vk_ensure_command_buffer_valid(metadata, queue_metadata) or_return

	vk_use_resource_set(metadata, command.resource_set)
	vk.CmdSetDepthTestEnableEXT(metadata.vk.command_buffer, false)
	vk.CmdPushConstants(
		metadata.vk.command_buffer,
		vk_render_pipeline_layout,
		{ .VERTEX, .FRAGMENT },
		0,
		64,
		raw_data(push_constant_buffer[:]),
	)
	vk.CmdBindPipeline(metadata.vk.command_buffer, .GRAPHICS, pipeline_metadata.vk.pipeline)
	vk.CmdBindIndexBuffer(
		metadata.vk.command_buffer,
		indices_metadata.vk.buffer,
		cast(vk.DeviceSize)indices_offset,
		vk_INDEX_TYPE_TO_VK[command.index_type],
	)
	vk.CmdDrawIndexed(
		metadata.vk.command_buffer,
		cast(u32)command.index_count,
		cast(u32)command.instance_count,
		0,
		0,
		0,
	)

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
	metadata.vk.pending_render_pass_signals = {}
	metadata.vk.pending_render_pass_waits = {}

	vk_ensure_command_buffer_valid(metadata, queue_metadata)

	for command in metadata.commands {
		switch v in command {
		case _Command_Mem_Copy:
			vk_emit_mem_copy(metadata, queue_metadata, v) or_return
		case _Command_Copy_Texture_To_Texture:
			vk_emit_copy_texture_to_texture(metadata, queue_metadata, v) or_return
		case _Command_Copy_Buffer_To_Texture:
			vk_emit_copy_buffer_to_texture(metadata, queue_metadata, v) or_return
		case _Command_Copy_Texture_To_Buffer:
			vk_emit_copy_texture_to_buffer(metadata, queue_metadata, v) or_return
		case _Command_Dispatch:
			vk_emit_dispatch(metadata, queue_metadata, v) or_return
		case _Command_Barrier:
			vk_emit_barrier(metadata, queue_metadata, v) or_return
		case _Command_Signal:
			vk_emit_signal(metadata, queue_metadata, v) or_return
		case _Command_Wait:
			vk_emit_wait(metadata, queue_metadata, v) or_return
		case _Command_Begin_Render_Pass:
			vk_emit_begin_render_pass(metadata, queue_metadata, v) or_return
		case _Command_End_Render_Pass:
			vk_emit_end_render_pass(metadata, queue_metadata, v) or_return
		case _Command_Draw:
			vk_emit_draw(metadata, queue_metadata, v) or_return
		case _Command_Draw_Indexed:
			vk_emit_draw_indexed(metadata, queue_metadata, v) or_return
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
	metadata.vk.pending_render_pass_signals = {}
	metadata.vk.pending_render_pass_waits = {}
	
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
	for wait in metadata.vk.pending_render_pass_waits {
		wait_count += len(wait.fences)
	}

	waits := make([dynamic]vk.SemaphoreSubmitInfo, 0, wait_count, metadata.allocator) or_return
	for fence in metadata.vk.pending_waits {
		fence_metadata, fence_res := _metadata_of(fence)
		_check_internal_emission_result(fence_res) or_return

		append(
			&waits,
			vk.SemaphoreSubmitInfo {
				sType		= .SEMAPHORE_SUBMIT_INFO,
				semaphore	= fence_metadata.vk.semaphore,
				value		= fence_metadata.vk.last_signaled_value,
				stageMask	= { .ALL_COMMANDS },
			},
		)
	}
	for wait in metadata.vk.pending_render_pass_waits {
		for fence in wait.fences {
			fence_metadata, fence_res := _metadata_of(fence)
			_check_internal_emission_result(fence_res) or_return

			append(
				&waits,
				vk.SemaphoreSubmitInfo {
					sType		= .SEMAPHORE_SUBMIT_INFO,
					semaphore	= fence_metadata.vk.semaphore,
					value		= fence_metadata.vk.last_signaled_value,
					stageMask	= vk_stages_to_vk(wait.before),
				},
			)
		}
	}

	if metadata.vk.is_first_command_buffer {
		for wait in metadata.semaphore_waits {
			semaphore_metadata, semaphore_res := _metadata_of(wait.semaphore)
			_check_internal_emission_result(semaphore_res) or_return

			append(
				&waits,
				vk.SemaphoreSubmitInfo {
					sType		= .SEMAPHORE_SUBMIT_INFO,
					semaphore	= semaphore_metadata.vk.semaphore,
					value		= cast(u64)wait.value,
					stageMask	= { .ALL_COMMANDS },
				},
			)
		}
	} else {
		append(
			&waits,
			vk.SemaphoreSubmitInfo {
				sType		= .SEMAPHORE_SUBMIT_INFO,
				semaphore	= metadata.vk.semaphore,
				value		= metadata.vk.semaphore_value,
				stageMask	= { .ALL_COMMANDS },
			},
		)
	}

	return waits[:], nil
}

vk_prepare_signal_semaphore_submit_infos :: proc(
	metadata:	^_Command_Buffer_Metadata,
	fences:		[]Fence,
) -> (infos: []vk.SemaphoreSubmitInfo, res: Result) {
	
	signal_count := len(fences)
	for signal in metadata.vk.pending_render_pass_signals {
		signal_count += len(signal.fences)
	}

	signals := make([dynamic]vk.SemaphoreSubmitInfo, 0, len(fences) + 1, metadata.allocator) or_return

	for fence in fences {
		fence_metadata, fence_res := _metadata_of(fence)
		_check_internal_emission_result(fence_res) or_return

		fence_metadata.vk.last_signaled_value += 1
		append(
			&signals,
			vk.SemaphoreSubmitInfo {
				sType		= .SEMAPHORE_SUBMIT_INFO,
				semaphore	= fence_metadata.vk.semaphore,
				value		= fence_metadata.vk.last_signaled_value,
				stageMask	= { .ALL_COMMANDS },
			},
		)
	}
	for signal in metadata.vk.pending_render_pass_signals {
		for fence in signal.fences {
			fence_metadata, fence_res := _metadata_of(fence)
			_check_internal_emission_result(fence_res) or_return

			fence_metadata.vk.last_signaled_value += 1
			append(
				&signals,
				vk.SemaphoreSubmitInfo {
					sType		= .SEMAPHORE_SUBMIT_INFO,
					semaphore	= fence_metadata.vk.semaphore,
					value		= fence_metadata.vk.last_signaled_value,
					stageMask	= vk_stages_to_vk(signal.after),
				},
			)
		}
	}
	append(
		&signals,
		vk.SemaphoreSubmitInfo {
			sType		= .SEMAPHORE_SUBMIT_INFO,
			semaphore	= metadata.vk.semaphore,
			value		= metadata.vk.semaphore_value + 1,
			stageMask	= { .ALL_COMMANDS },
		},
	)

	return signals[:], nil
}

vk_stages_to_vk :: proc(stages: Stages) -> (flags: vk.PipelineStageFlags2) {
	for stage in stages {
		flags += vk_STAGE_TO_VK[stage]
	}

	return
}

vk_origin_to_vk_offset :: proc(origin: [3]int) -> vk.Offset3D {
	return {
		cast(i32)origin.x,
		cast(i32)origin.y,
		cast(i32)origin.z,
	}
}

vk_size_to_vk_extent :: proc(size: [3]int) -> vk.Extent3D {
	return {
		cast(u32)size.x,
		cast(u32)size.y,
		cast(u32)size.z,
	}
}

vk_STAGE_TO_VK := [Stage]vk.PipelineStageFlags2 {
	.Transfer			= { .TRANSFER },
	.Compute			= { .COMPUTE_SHADER },
	.Vertex				= { .VERTEX_INPUT },
	.Fragment			= { .FRAGMENT_SHADER },
	.Color_Attachment		= { .COLOR_ATTACHMENT_OUTPUT },
	.Depth_Stencil_Attachment	= { .EARLY_FRAGMENT_TESTS, .LATE_FRAGMENT_TESTS },
}

@(rodata)
vk_LOAD_OPERATION_TO_VK := [Load_Operation]vk.AttachmentLoadOp {
	.Clear		= .CLEAR,
	.Load		= .LOAD,
	.Dont_Care	= .DONT_CARE,
}

@(rodata)
vk_STORE_OPERATION_TO_VK := [Store_Operation]vk.AttachmentStoreOp {
	.Store		= .STORE,
	.Dont_Care	= .DONT_CARE,
}

@(rodata)
vk_INDEX_TYPE_TO_VK := [Index_Type]vk.IndexType {
	.U16	= .UINT16,
	.U32	= .UINT32,
}

