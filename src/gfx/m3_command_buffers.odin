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

	wait_set:		[]Fence,
}

m3_setup_command_buffer :: proc(metadata: ^_Command_Buffer_Metadata, queue_metadata: ^_Queue_Metadata) -> Result {
	return nil
}

m3_emit_mem_copy :: proc(
	metadata:	^_Command_Buffer_Metadata,
	queue_metadata:	^_Queue_Metadata,
	command:	_Command_Mem_Copy,
) -> Result {
	
	source_metadata, source_res := _metadata_of(command.source)
	if source_res != nil do return .Use_After_Free

	destination_metadata, destination_res := _metadata_of(command.destination)
	if destination_res != nil do return .Use_After_Free

	source_offset := _offset_from_base(command.source, source_metadata)
	destination_offset := _offset_from_base(command.destination, destination_metadata)

	m3_enable_blit_encoder(metadata)
	metadata.m3.blit_encoder->copyFromBuffer(
		source_metadata.m3.buffer,
		cast(NS.UInteger)source_offset,
		destination_metadata.m3.buffer,
		cast(NS.UInteger)destination_offset,
		cast(NS.UInteger)command.size,
	)

	return nil
}

m3_emit_dispatch :: proc(
	metadata:	^_Command_Buffer_Metadata,
	queue_metadata:	^_Queue_Metadata,
	command:	_Command_Dispatch,
) -> Result {

	m3_enable_compute_encoder(metadata)

	pipeline_metadata, pipeline_res := _metadata_of(command.pipeline)
	if pipeline_res != nil do return .Use_After_Free

	group_size := pipeline_metadata.compute.group_size

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

	// NOTE: In Metal 3, encoders are executed in encoding order. All operations encoded in render and blit
	//	encoders are executed in encoding order.
	//	The only encoder that would require synchronization is the compute one, since it si created with the
	//	`.Concurrent` dispatch mode.
	if .Compute in command.before && metadata.m3.current_encoder == .Compute {
		m3_flush_encoder(metadata)
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
			if fence_res != nil do return .Use_After_Free
			
			metadata.m3.blit_encoder->updateFence(fence_metadata.m3.fence)
		}

	case .Compute:
		for fence in command.signals {
			fence_metadata, fence_res := _metadata_of(fence)
			if fence_res != nil do return .Use_After_Free
			
			metadata.m3.compute_encoder->updateFence(fence_metadata.m3.fence)
		}

	case .Render:
		// TODO: Make renderpass signals and waits have stages.

		// for fence in command.signals {
		// 	fence_metadata, fence_res := _metadata_of(fence)
		// 	if fence_res != nil do return .Use_After_Free
			
		// 	metadata.m3.render_encoder->updateFence(fence_metadata.m3.fence, { .Fragment })
		// }

	case .None:
		m3_enable_blit_encoder(metadata)
		for fence in command.signals {
			fence_metadata, fence_res := _metadata_of(fence)
			if fence_res != nil do return .Use_After_Free
			
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

	metadata.m3.wait_set	= command.waits
	return nil
}

m3_emit_commands :: proc(metadata: ^_Command_Buffer_Metadata, queue_metadata: ^_Queue_Metadata) -> Result {

	metadata.m3.command_buffer = queue_metadata.m3.queue->commandBuffer()

	for command in metadata.commands {
		switch v in command {
		case _Command_Mem_Copy:	m3_emit_mem_copy(metadata, queue_metadata, v) or_return
		case _Command_Dispatch:	m3_emit_dispatch(metadata, queue_metadata, v) or_return
		case _Command_Barrier:	m3_emit_barrier(metadata, queue_metadata, v) or_return
		case _Command_Signal:	m3_emit_signal(metadata, queue_metadata, v) or_return
		case _Command_Wait:	m3_emit_wait(metadata, queue_metadata, v) or_return
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
	for command_buffer in command_buffers {
		metadata, metadata_res := _metadata_of(command_buffer)
		if metadata_res != nil do return .Use_After_Free

		m3_emit_commands(metadata, queue_metadata) or_return
	}

	if len(signals) > 0 {
		command_buffer := queue_metadata.m3.queue->commandBuffer()

		for signal in signals {
			semaphore_metadata, semaphore_res := _metadata_of(signal.semaphore)
			if semaphore_res != nil do return .Use_After_Free

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

	for fence in metadata.m3.wait_set {
		fence_metadata := _metadata_of(fence) or_continue

		metadata.m3.blit_encoder->waitForFence(fence_metadata.m3.fence)
	}
	metadata.m3.wait_set = {}
}

m3_enable_compute_encoder :: proc(metadata: ^_Command_Buffer_Metadata) {
	if metadata.m3.current_encoder == .Compute {
		return
	}

	m3_flush_encoder(metadata)

	metadata.m3.compute_encoder = metadata.m3.command_buffer->computeCommandEncoderWithDispatchType(.Concurrent)
	metadata.m3.current_encoder = .Compute

	metadata.m3.compute_encoder->useHeaps(m3_residency_set[:])

	for fence in metadata.m3.wait_set {
		fence_metadata := _metadata_of(fence) or_continue

		metadata.m3.compute_encoder->waitForFence(fence_metadata.m3.fence)
	}
	metadata.m3.wait_set = {}
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

