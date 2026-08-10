#+build darwin
package gfx

import NS "core:sys/darwin/Foundation"
import MTL "vendor:darwin/Metal"

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
}

m3_setup_command_buffer :: proc(metadata: ^_Command_Buffer_Metadata, queue_metadata: ^_Queue_Metadata) -> Result {
	return nil
}

m3_begin_command_encoding :: proc(metadata: ^_Command_Buffer_Metadata, queue_metadata: ^_Queue_Metadata) -> Result {
	metadata.m3.command_buffer = queue_metadata.m3.queue->commandBufferWithUnretainedReferences()
	metadata.m3.current_encoder = .None

	return nil
}

m3_use_resources :: proc(
	metadata: ^_Command_Buffer_Metadata,
	resource_set_metadata: ^_Resource_Set_Metadata,
) -> Result {
	metadata.m3.is_resource_set_bound = false

	return nil
}

m3_mem_copy :: proc(
	metadata:		^_Command_Buffer_Metadata,
	destination_metadata:	^_Buffer_Metadata,
	destination_offset:	uintptr,
	source_metadata:	^_Buffer_Metadata,
	source_offset:		uintptr,
	length:			int,
) -> Result {

	m3_enable_blit_encoder(metadata)
	metadata.m3.blit_encoder->copyFromBuffer(
		source_metadata.m3.buffer,
		cast(NS.UInteger)source_offset,
		destination_metadata.m3.buffer,
		cast(NS.UInteger)destination_offset,
		cast(NS.UInteger)length,
	)

	return nil
}

m3_dispatch :: proc(
	metadata:		^_Command_Buffer_Metadata,
	pipeline_metadata:	^_Pipeline_Metadata,
	argument:		[]byte,
	group_count:		[3]int,
) -> Result {
	
	m3_enable_compute_encoder(metadata)

	group_size := pipeline_metadata.compute.group_size

	m3_bind_resource_set(metadata) or_return
	metadata.m3.compute_encoder->setBytes(argument, 0)
	metadata.m3.compute_encoder->setComputePipelineState(pipeline_metadata.m3.compute.pipeline)
	metadata.m3.compute_encoder->dispatchThreadgroups(
		{ cast(NS.Integer)group_count.x, cast(NS.Integer)group_count.y, cast(NS.Integer)group_count.z },
		{ cast(NS.Integer)group_size.x, cast(NS.Integer)group_size.y, cast(NS.Integer)group_size.z },
	)

	return nil
}

m3_barrier :: proc(metadata: ^_Command_Buffer_Metadata, after: Stages, before: Stages) -> Result {
	// NOTE: In Metal 3, encoders are executed in encoding order. All operations encoded in render and blit
	//	encoders are executed in encoding order.
	//	The only encoder that would require synchronization is the compute one, since it si created with the
	//	`.Concurrent` dispatch mode.
	if .Compute in before && metadata.m3.current_encoder == .Compute {
		m3_flush_encoder(metadata)
	}

	return nil
}

m3_submit :: proc(metadata: ^_Command_Buffer_Metadata, queue_metadata: ^_Queue_Metadata) -> Result {
	m3_flush_encoder(metadata)

	metadata.m3.command_buffer->commit()

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

	resource_set_metadata := _metadata_of(metadata.resource_set) or_return

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

m3_enable_blit_encoder :: proc(metadata: ^_Command_Buffer_Metadata) {
	if metadata.m3.current_encoder == .Blit {
		return
	}

	m3_flush_encoder(metadata)

	metadata.m3.blit_encoder = metadata.m3.command_buffer->blitCommandEncoder()
	metadata.m3.current_encoder = .Blit
}

m3_enable_compute_encoder :: proc(metadata: ^_Command_Buffer_Metadata) {
	if metadata.m3.current_encoder == .Compute {
		return
	}

	m3_flush_encoder(metadata)

	metadata.m3.compute_encoder = metadata.m3.command_buffer->computeCommandEncoderWithDispatchType(.Concurrent)
	metadata.m3.current_encoder = .Compute

	metadata.m3.compute_encoder->useHeaps(m3_residency_set[:])
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

