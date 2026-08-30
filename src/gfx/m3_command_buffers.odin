#+build darwin
package gfx

import NS "core:sys/darwin/Foundation"
import MTL "vendor:darwin/Metal"
import MTLe "darwext/metal"

m3_Current_Encoder :: enum {
	None,
	Compute,
	Blit,
	Render,
}

m3_Command_Buffer_Metadata :: struct {
	command_buffer:		^MTL.CommandBuffer,

	current_encoder:	m3_Current_Encoder,

	compute_encoder:	^MTL.ComputeCommandEncoder,
	blit_encoder:		^MTL.BlitCommandEncoder,
	render_encoder:		^MTL.RenderCommandEncoder,

	is_resource_set_bound:	bool,

	barrier_fence:		^MTL.Fence,
	barrier_fence_pending:	bool,

	wait_set:		[]Fence,
}

m3_setup_command_buffer :: proc(metadata: ^_Command_Buffer_Metadata, queue_metadata: ^_Queue_Metadata) -> Result {
	metadata.m3.barrier_fence = m3_device->newFence()
	if metadata.m3.barrier_fence == nil {
		return .Out_Of_Gpu_Memory
	}

	return nil
}

m3_destroy_command_buffer :: proc(metadata: ^_Command_Buffer_Metadata, queue_metadata: ^_Queue_Metadata) {
	metadata.m3.barrier_fence->release()
}

m3_emit_mem_copy :: proc(
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

	m3_enable_blit_encoder(metadata) or_return
	metadata.m3.blit_encoder->copyFromBuffer(
		source_metadata.m3.buffer,
		cast(NS.UInteger)source_offset,
		destination_metadata.m3.buffer,
		cast(NS.UInteger)destination_offset,
		cast(NS.UInteger)command.size,
	)

	return nil
}

m3_emit_copy_texture_to_texture :: proc(
	metadata:	^_Command_Buffer_Metadata,
	queue_metadata:	^_Queue_Metadata,
	command:	_Command_Copy_Texture_To_Texture,
) -> Result {

	source_metadata, source_res := _metadata_of(command.source)
	_check_internal_emission_result(source_res) or_return

	destination_metadata, destination_res := _metadata_of(command.destination)
	_check_internal_emission_result(destination_res) or_return

	m3_enable_blit_encoder(metadata) or_return
	for i in 0..<command.source_region.layer_count {
		source_layer := command.source_region.base_layer + i
		destination_layer := command.destination_region.base_layer + i

		metadata.m3.blit_encoder->copyFromTextureWithDestinationOrigin(
			source_metadata.m3.texture,
			cast(NS.UInteger)source_layer,
			cast(NS.UInteger)command.source_region.mip,
			m3_origin_to_mtl(command.source_region.origin),
			m3_size_to_mtl(command.source_region.size),
			destination_metadata.m3.texture,
			cast(NS.UInteger)destination_layer,
			cast(NS.UInteger)command.destination_region.mip,
			m3_origin_to_mtl(command.destination_region.origin),
		)
	}
	
	return nil
}

m3_emit_copy_buffer_to_texture :: proc(
	metadata:	^_Command_Buffer_Metadata,
	queue_metadata:	^_Queue_Metadata,
	command:	_Command_Copy_Buffer_To_Texture,
) -> Result {

	source_metadata, source_res := _metadata_of(command.source)
	_check_internal_emission_result(source_res) or_return
	source_offset := _offset_from_base(command.source, source_metadata)

	texture_metadata, texture_res := _metadata_of(command.texture)
	_check_internal_emission_result(texture_res) or_return

	layer_size := _size_of_texture_region_layer(texture_metadata, command.region)
	row_size := _size_of_texture_region_row(texture_metadata, command.region)
	image_size := _size_of_texture_region_2d_image(texture_metadata, command.region)

	m3_enable_blit_encoder(metadata) or_return
	for i in 0..<command.region.layer_count {
		metadata.m3.blit_encoder->copyFromBufferEx(
			source_metadata.m3.buffer,
			cast(NS.UInteger)(cast(int)source_offset + layer_size * i),
			cast(NS.UInteger)row_size,
			cast(NS.UInteger)(command.region.size.z == 1 ? 0 : image_size),
			m3_size_to_mtl(command.region.size),
			texture_metadata.m3.texture,
			cast(NS.UInteger)(command.region.base_layer + i),
			cast(NS.UInteger)command.region.mip,
			m3_origin_to_mtl(command.region.origin),
		)
	}

	return nil
}

m3_emit_copy_texture_to_buffer :: proc(
	metadata:	^_Command_Buffer_Metadata,
	queue_metadata:	^_Queue_Metadata,
	command:	_Command_Copy_Texture_To_Buffer,
) -> Result {

	destination_metadata, destination_res := _metadata_of(command.destination)
	_check_internal_emission_result(destination_res) or_return
	destination_offset := _offset_from_base(command.destination, destination_metadata)

	texture_metadata, texture_res := _metadata_of(command.texture)
	_check_internal_emission_result(texture_res) or_return

	layer_size := _size_of_texture_region_layer(texture_metadata, command.region)
	row_size := _size_of_texture_region_row(texture_metadata, command.region)
	image_size := _size_of_texture_region_2d_image(texture_metadata, command.region)

	m3_enable_blit_encoder(metadata) or_return
	for i in 0..<command.region.layer_count {
		metadata.m3.blit_encoder->copyFromTextureEx(
			texture_metadata.m3.texture,
			cast(NS.UInteger)(command.region.base_layer + i),
			cast(NS.UInteger)command.region.mip,
			m3_origin_to_mtl(command.region.origin),
			m3_size_to_mtl(command.region.size),
			destination_metadata.m3.buffer,
			cast(NS.UInteger)(cast(int)destination_offset + layer_size * i),
			cast(NS.UInteger)row_size,
			cast(NS.UInteger)(command.region.size.z == 1 ? 0 : image_size),
		)
	}

	return nil
}

m3_emit_dispatch :: proc(
	metadata:	^_Command_Buffer_Metadata,
	queue_metadata:	^_Queue_Metadata,
	command:	_Command_Dispatch,
) -> Result {

	pipeline_metadata, pipeline_res := _metadata_of(command.pipeline)
	_check_internal_emission_result(pipeline_res) or_return

	group_size := pipeline_metadata.compute.group_size

	m3_enable_compute_encoder(metadata) or_return
	m3_bind_resource_set(metadata) or_return
	metadata.m3.compute_encoder->setBytes(command.argument, 0)
	metadata.m3.compute_encoder->setComputePipelineState(pipeline_metadata.m3.compute.pipeline)
	metadata.m3.compute_encoder->dispatchThreadgroups(
		{
			cast(NS.Integer)command.group_count.x,
			cast(NS.Integer)command.group_count.y,
			cast(NS.Integer)command.group_count.z,
		},
		{ cast(NS.Integer)group_size.x, cast(NS.Integer)group_size.y, cast(NS.Integer)group_size.z },
	)

	return nil
}

m3_emit_barrier :: proc(
	metadata: ^_Command_Buffer_Metadata,
	queue_metadata: ^_Queue_Metadata,
	command: _Command_Barrier,
) -> Result {

	if metadata.m3.current_encoder != .None {
		switch metadata.m3.current_encoder {
		case .None:
		case .Blit:
			metadata.m3.blit_encoder->updateFence(metadata.m3.barrier_fence)
		case .Compute:
			metadata.m3.compute_encoder->updateFence(metadata.m3.barrier_fence)
		case .Render:
			panic("Barriers are not allowed during render passes.")
		}
		m3_flush_encoder(metadata)
		metadata.m3.barrier_fence_pending = true
	}

	return nil
}

m3_emit_signal :: proc(
	metadata:	^_Command_Buffer_Metadata,
	queue_metadata:	^_Queue_Metadata,
	command:	_Command_Signal,
) -> Result {

	switch metadata.m3.current_encoder {
	case .Blit:
		for fence in command.signals {
			fence_metadata, fence_res := _metadata_of(fence)
			_check_internal_emission_result(fence_res) or_return
			
			metadata.m3.blit_encoder->updateFence(fence_metadata.m3.fence)
		}

	case .Compute:
		for fence in command.signals {
			fence_metadata, fence_res := _metadata_of(fence)
			_check_internal_emission_result(fence_res) or_return
			
			metadata.m3.compute_encoder->updateFence(fence_metadata.m3.fence)
		}

	case .Render:
		panic("It is not possible to emit signals during render passes.")

	case .None:
		m3_enable_blit_encoder(metadata)
		for fence in command.signals {
			fence_metadata, fence_res := _metadata_of(fence)
			_check_internal_emission_result(fence_res) or_return
			
			metadata.m3.blit_encoder->updateFence(fence_metadata.m3.fence)
		}
	}

	return nil
}

m3_emit_wait :: proc(
	metadata:	^_Command_Buffer_Metadata,
	queue_metadata:	^_Queue_Metadata,
	command:	_Command_Wait,
) -> Result {

	assert(metadata.m3.current_encoder != .Render, "It is not possible to emit waits during render passes.")
	
	metadata.m3.wait_set	= command.waits
	return nil
}

m3_emit_begin_render_pass :: proc(
	metadata: ^_Command_Buffer_Metadata,
	queue_metadata: ^_Queue_Metadata,
	command: _Command_Begin_Render_Pass,
) -> Result {

	descriptor := MTL.RenderPassDescriptor.alloc()->init()
	defer descriptor->release()

	for color_attachment, i in command.color_attachments {
		view_metadata, view_res := _metadata_of(color_attachment.view)
		_check_internal_emission_result(view_res) or_return

		mtl_color_attachment := MTL.RenderPassColorAttachmentDescriptor.alloc()->init()
		defer mtl_color_attachment->release()

		mtl_color_attachment->setClearColor(m3_clear_color_to_mtl(color_attachment.clear_value.([4]f64)))
		mtl_color_attachment->setLoadAction(m3_LOAD_OPERATION_TO_MTL[color_attachment.load_operation])
		mtl_color_attachment->setStoreAction(m3_STORE_OPERATION_TO_MTL[color_attachment.store_operation])
		mtl_color_attachment->setTexture(view_metadata.m3.view)

		descriptor->colorAttachments()->setObject(mtl_color_attachment, cast(NS.UInteger)i)
	}

	if depth_attachment, has_depth_attachment := command.depth_attachment.?; has_depth_attachment {
		view_metadata, view_res := _metadata_of(depth_attachment.view)
		_check_internal_emission_result(view_res) or_return

		mtl_depth_attachment := MTL.RenderPassDepthAttachmentDescriptor.alloc()->init()
		defer mtl_depth_attachment->release()

		mtl_depth_attachment->setClearDepth(depth_attachment.clear_value.(f64))
		mtl_depth_attachment->setLoadAction(m3_LOAD_OPERATION_TO_MTL[depth_attachment.load_operation])
		mtl_depth_attachment->setStoreAction(m3_STORE_OPERATION_TO_MTL[depth_attachment.store_operation])
		mtl_depth_attachment->setTexture(view_metadata.m3.view)

		descriptor->setDepthAttachment(mtl_depth_attachment)
	}

	if stencil_attachment, has_stencil_attachment := command.stencil_attachment.?; has_stencil_attachment {
		view_metadata, view_res := _metadata_of(stencil_attachment.view)
		_check_internal_emission_result(view_res) or_return

		mtl_stencil_attachment := MTL.RenderPassStencilAttachmentDescriptor.alloc()->init()
		defer mtl_stencil_attachment->release()

		mtl_stencil_attachment->setClearStencil(stencil_attachment.clear_value.(u32))
		(cast(^MTL.RenderPassAttachmentDescriptor)mtl_stencil_attachment)->setLoadAction(
			m3_LOAD_OPERATION_TO_MTL[stencil_attachment.load_operation])
		(cast(^MTL.RenderPassAttachmentDescriptor)mtl_stencil_attachment)->setStoreAction(
			m3_STORE_OPERATION_TO_MTL[stencil_attachment.store_operation])
		(cast(^MTL.RenderPassAttachmentDescriptor)mtl_stencil_attachment)->setTexture(view_metadata.m3.view)

		descriptor->setStencilAttachment(mtl_stencil_attachment)
	}

	m3_enable_render_encoder(metadata, descriptor)

	return nil
}

m3_emit_end_render_pass :: proc(
	metadata: ^_Command_Buffer_Metadata,
	queue_metadata: ^_Queue_Metadata,
	command: _Command_End_Render_Pass,
) -> Result {

	assert(metadata.m3.current_encoder == .Render)
	
	metadata.m3.render_encoder->updateFence(metadata.m3.barrier_fence, { .Vertex, .Fragment })
	metadata.m3.barrier_fence_pending = true
	
	m3_flush_encoder(metadata)

	return nil
}

m3_emit_draw :: proc(
	metadata:	^_Command_Buffer_Metadata,
	queue_metadata:	^_Queue_Metadata,
	command:	_Command_Draw,
) -> Result {

	assert(metadata.m3.current_encoder == .Render)

	pipeline_metadata, pipeline_res := _metadata_of(command.pipeline)
	_check_internal_emission_result(pipeline_res) or_return

	m3_bind_resource_set(metadata) or_return
	metadata.m3.render_encoder->setVertexBytes(command.argument, 0)
	metadata.m3.render_encoder->setFragmentBytes(command.argument, 0)
	metadata.m3.render_encoder->setRenderPipelineState(pipeline_metadata.m3.render.pipeline)
	metadata.m3.render_encoder->drawPrimitivesWithInstanceCount(
		m3_TOPOLOGY_TO_MTL[pipeline_metadata.render.topology],
		cast(NS.UInteger)command.base_vertex,
		cast(NS.UInteger)command.vertex_count,
		cast(NS.UInteger)command.instance_count,
	)

	return nil
}

m3_emit_draw_indexed :: proc(
	metadata:	^_Command_Buffer_Metadata,
	queue_metadata:	^_Queue_Metadata,
	command:	_Command_Draw_Indexed,
) -> Result {

	assert(metadata.m3.current_encoder == .Render)

	pipeline_metadata, pipeline_res := _metadata_of(command.pipeline)
	_check_internal_emission_result(pipeline_res) or_return

	indices_metadata, indices_res := _metadata_of(command.indices)
	_check_internal_emission_result(indices_res) or_return
	indices_offset := _offset_from_base(command.indices, indices_metadata)

	m3_bind_resource_set(metadata) or_return
	metadata.m3.render_encoder->setVertexBytes(command.argument, 0)
	metadata.m3.render_encoder->setFragmentBytes(command.argument, 0)
	metadata.m3.render_encoder->setRenderPipelineState(pipeline_metadata.m3.render.pipeline)
	metadata.m3.render_encoder->drawIndexedPrimitivesWithInstanceCount(
		m3_TOPOLOGY_TO_MTL[pipeline_metadata.render.topology],
		cast(NS.UInteger)command.index_count,
		m3_INDEX_TYPE_TO_MTL[command.index_type],
		indices_metadata.m3.buffer,
		cast(NS.UInteger)indices_offset,
		cast(NS.UInteger)command.instance_count,
	)

	return nil
}

m3_emit_commands :: proc(metadata: ^_Command_Buffer_Metadata, queue_metadata: ^_Queue_Metadata) -> Result {

	metadata.m3.wait_set = {}	
	metadata.m3.is_resource_set_bound = false
	metadata.m3.barrier_fence_pending = false

	metadata.m3.command_buffer = queue_metadata.m3.queue->commandBuffer()
	MTLe.CommandBuffer_useResidencySet(auto_cast metadata.m3.command_buffer, m3_residency_set)

	for wait in metadata.semaphore_waits {
		semaphore_metadata, semaphore_res := _metadata_of(wait.semaphore)
		_check_internal_emission_result(semaphore_res) or_return

		switch semaphore_metadata.type {
		case .Default:
			metadata.m3.command_buffer->encodeWaitForEvent(
				semaphore_metadata.m3.event, cast(u64)wait.value)

		case .Cpu_Waitable:
			metadata.m3.command_buffer->encodeWaitForEvent(
				semaphore_metadata.m3.shared_event, cast(u64)wait.value)
		}
	}

	for command in metadata.commands {
		switch v in command {
		case _Command_Mem_Copy:
			m3_emit_mem_copy(metadata, queue_metadata, v)or_return
		case _Command_Copy_Texture_To_Texture:
			m3_emit_copy_texture_to_texture(metadata, queue_metadata, v) or_return
		case _Command_Copy_Buffer_To_Texture:
			m3_emit_copy_buffer_to_texture(metadata, queue_metadata, v) or_return
		case _Command_Copy_Texture_To_Buffer:
			m3_emit_copy_texture_to_buffer(metadata, queue_metadata, v) or_return
		case _Command_Dispatch:
			m3_emit_dispatch(metadata, queue_metadata, v) or_return
		case _Command_Barrier:
			m3_emit_barrier(metadata, queue_metadata, v) or_return
		case _Command_Signal:
			m3_emit_signal(metadata, queue_metadata, v) or_return
		case _Command_Wait:
			m3_emit_wait(metadata, queue_metadata, v) or_return
		case _Command_Begin_Render_Pass:
			m3_emit_begin_render_pass(metadata, queue_metadata, v) or_return
		case _Command_End_Render_Pass:
			m3_emit_end_render_pass(metadata, queue_metadata, v) or_return
		case _Command_Draw:
			m3_emit_draw(metadata, queue_metadata, v) or_return
		case _Command_Draw_Indexed:
			m3_emit_draw_indexed(metadata, queue_metadata, v) or_return
		}
	}

	m3_flush_encoder(metadata)
	metadata.m3.command_buffer->commit()

	return nil
}

m3_submit :: proc(
	queue_metadata: ^_Queue_Metadata,
	command_buffers: []Command_Buffer,
	signals: []Semaphore_Signal,
) -> Result {
	NS.scoped_autoreleasepool()

	for command_buffer in command_buffers {
		metadata, metadata_res := _metadata_of(command_buffer)
		_check_internal_emission_result(metadata_res) or_return

		m3_emit_commands(metadata, queue_metadata) or_return
	}

	if len(signals) > 0 {
		command_buffer := queue_metadata.m3.queue->commandBuffer()

		for signal in signals {
			semaphore_metadata, semaphore_res := _metadata_of(signal.semaphore)
			_check_internal_emission_result(semaphore_res) or_return

			if semaphore_metadata.type == .Default {
				command_buffer->encodeSignalEvent(semaphore_metadata.m3.event, cast(u64)signal.value)
			} else {
				command_buffer->encodeSignalEvent(
					semaphore_metadata.m3.shared_event,
					cast(u64)signal.value,
				)
			}
		}

		command_buffer->commit()
	}

	return nil
}

m3_bind_resource_set :: proc(metadata: ^_Command_Buffer_Metadata) -> Result {
	assert(metadata.m3.current_encoder != .Blit)
	if metadata.m3.current_encoder == .None {
		return nil
	}
	if metadata.m3.is_resource_set_bound {
		return nil
	}

	resource_set_metadata, resource_set_res := _metadata_of(metadata.resource_set)
	_check_internal_emission_result(resource_set_res) or_return

	#partial switch metadata.m3.current_encoder {
	case .Compute:
		metadata.m3.compute_encoder->setBuffer(resource_set_metadata.m3.root_buffer, 0, 1)

	case .Render:
		metadata.m3.render_encoder->setVertexBuffer(resource_set_metadata.m3.root_buffer, 0, 1)
		metadata.m3.render_encoder->setFragmentBuffer(resource_set_metadata.m3.root_buffer, 0, 1)
	}

	metadata.m3.is_resource_set_bound = true

	return nil
}

m3_enable_blit_encoder :: proc(metadata: ^_Command_Buffer_Metadata) -> Result {
	if metadata.m3.current_encoder == .Blit {
		return nil
	}

	m3_flush_encoder(metadata)

	metadata.m3.blit_encoder = metadata.m3.command_buffer->blitCommandEncoder()
	metadata.m3.current_encoder = .Blit

	for fence in metadata.m3.wait_set {
		fence_metadata, fence_res := _metadata_of(fence)
		_check_internal_emission_result(fence_res) or_return

		metadata.m3.blit_encoder->waitForFence(fence_metadata.m3.fence)
	}
	metadata.m3.wait_set = {}
	if metadata.m3.barrier_fence_pending {
		metadata.m3.blit_encoder->waitForFence(metadata.m3.barrier_fence)
		metadata.m3.barrier_fence_pending = false
	}

	return nil
}

m3_enable_compute_encoder :: proc(metadata: ^_Command_Buffer_Metadata) -> Result {
	if metadata.m3.current_encoder == .Compute {
		return nil
	}

	m3_flush_encoder(metadata)

	metadata.m3.compute_encoder = metadata.m3.command_buffer->computeCommandEncoderWithDispatchType(.Concurrent)
	metadata.m3.current_encoder = .Compute

	for fence in metadata.m3.wait_set {
		fence_metadata, fence_res := _metadata_of(fence)
		_check_internal_emission_result(fence_res) or_return

		metadata.m3.compute_encoder->waitForFence(fence_metadata.m3.fence)
	}
	metadata.m3.wait_set = {}
	if metadata.m3.barrier_fence_pending {
		metadata.m3.compute_encoder->waitForFence(metadata.m3.barrier_fence)
		metadata.m3.barrier_fence_pending = false
	}

	return nil
}

m3_enable_render_encoder :: proc(metadata: ^_Command_Buffer_Metadata, descriptor: ^MTL.RenderPassDescriptor) -> Result {
	m3_flush_encoder(metadata)

	metadata.m3.render_encoder = metadata.m3.command_buffer->renderCommandEncoderWithDescriptor(descriptor)
	metadata.m3.current_encoder = .Render

	for fence in metadata.m3.wait_set {
		fence_metadata, fence_res := _metadata_of(fence)
		_check_internal_emission_result(fence_res) or_return

		metadata.m3.render_encoder->waitForFence(fence_metadata.m3.fence, { .Vertex })
	}
	metadata.m3.wait_set = {}
	if metadata.m3.barrier_fence_pending {
		metadata.m3.render_encoder->waitForFence(metadata.m3.barrier_fence, { .Vertex })
		metadata.m3.barrier_fence_pending = false
	}

	return nil
}

m3_flush_encoder :: proc(metadata: ^_Command_Buffer_Metadata) {
	switch metadata.m3.current_encoder {
	case .None:
	case .Compute:
		metadata.m3.compute_encoder->endEncoding()
		metadata.m3.compute_encoder = nil
	case .Blit:
		metadata.m3.blit_encoder->endEncoding()
		metadata.m3.blit_encoder = nil
	case .Render:
		metadata.m3.render_encoder->endEncoding()
		metadata.m3.render_encoder = nil
	}
	
	metadata.m3.current_encoder = .None
	metadata.m3.is_resource_set_bound = false
}

m3_size_to_mtl :: proc(size: [3]int) -> MTL.Size {
	return {
		cast(NS.Integer)size.x,
		cast(NS.Integer)size.y,
		cast(NS.Integer)size.z,
	}
}

m3_origin_to_mtl :: proc(origin: [3]int) -> MTL.Origin {
	return {
		cast(NS.Integer)origin.x,
		cast(NS.Integer)origin.y,
		cast(NS.Integer)origin.z,
	}
}

m3_clear_color_to_mtl :: proc(clear_color: [4]f64) -> MTL.ClearColor {
	return {
		**clear_color,
	}
}

@(rodata)
m3_LOAD_OPERATION_TO_MTL := [Load_Operation]MTL.LoadAction {
	.Clear		= .Clear,
	.Load		= .Load,
	.Dont_Care	= .DontCare,
}

@(rodata)
m3_STORE_OPERATION_TO_MTL := [Store_Operation]MTL.StoreAction {
	.Store		= .Store,
	.Dont_Care	= .DontCare,
}

@(rodata)
m3_INDEX_TYPE_TO_MTL := [Index_Type]MTL.IndexType {
	.U16	= .UInt16,
	.U32	= .UInt32,
}
