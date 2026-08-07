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
}

m3_setup_command_buffer :: proc(metadata: ^_Command_Buffer_Metadata, queue_metadata: ^_Queue_Metadata) -> Result {
	return nil
}

m3_begin_command_encoding :: proc(metadata: ^_Command_Buffer_Metadata, queue_metadata: ^_Queue_Metadata) -> Result {
	metadata.m3.command_buffer = queue_metadata.m3.queue->commandBufferWithUnretainedReferences()
	metadata.m3.current_encoder = .None

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

m3_enable_blit_encoder :: proc(metadata: ^_Command_Buffer_Metadata) {
	m3_flush_encoder(metadata)

	metadata.m3.blit_encoder = metadata.m3.command_buffer->blitCommandEncoder()
	metadata.m3.current_encoder = .Blit
}

m3_enable_compute_encoder :: proc(metadata: ^_Command_Buffer_Metadata) {
	m3_flush_encoder(metadata)

	metadata.m3.compute_encoder = metadata.m3.command_buffer->computeCommandEncoderWithDispatchType(.Concurrent)
	metadata.m3.current_encoder = .Compute
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
}

