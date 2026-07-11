#+build darwin
package gfx

import "core:mem"
import hm "core:container/handle_map"
import NS "core:sys/darwin/Foundation"
import MTL "vendor:darwin/Metal"

_Mtl_Stage :: enum {
	None,
	Blit,
	Compute,
	Render,
}

_Bound_Buffer :: struct {
	heap:	^MTL.Heap,
	buffer:	^MTL.Buffer,
	offset:	uintptr,
}

_Command_Buffer_Metadata :: struct {
	handle:	Command_Buffer,

	current_encoding:	_Mtl_Stage,

	pipeline:		Pipeline,
	accessed_heaps:		[]^MTL.Heap,
	texture_heap:		[]MTL.ResourceID,
	buffers:		[Raster_Stage][8]_Bound_Buffer,

	command_buffer:		^MTL.CommandBuffer,

	blit_encoder:		^MTL.BlitCommandEncoder,
	compute_encoder:	^MTL.ComputeCommandEncoder,
	render_encoder:		^MTL.RenderCommandEncoder,
}

_queue:			^MTL.CommandQueue
_command_buffers:	hm.Dynamic_Handle_Map(_Command_Buffer_Metadata, Command_Buffer)

_start_command_encoding :: proc() -> (cb: Command_Buffer, res: Result) {
	cb = hm.add(&_command_buffers, _Command_Buffer_Metadata {}) or_return

	return cb, nil
}

_mem_copy :: proc(cb: Command_Buffer, destination: Buffer, source: Buffer, size: int) -> Result #no_type_assert {
	metadata, metadata_ok := hm.get(&_command_buffers, cb)
	if !metadata_ok {
		return .Invalid_Command_Buffer
	}

	source_metadata, source_ok := hm.get(&_buffers, source.handle)
	if !source_ok {
		return .Invalid_Buffer
	}

	dest_metadata, dest_ok := hm.get(&_buffers, destination.handle)
	if !dest_ok {
		return .Invalid_Buffer
	}

	source_offset := _offset_from_base(source, source_metadata)
	dest_offset := _offset_from_base(destination, dest_metadata)

	_ensure_valid_blit_encoder(metadata)
	metadata.blit_encoder->copyFromBuffer(
		source_metadata.buffer,
		cast(NS.UInteger)source_offset,
		dest_metadata.buffer,
		cast(NS.UInteger)dest_offset,
		cast(NS.UInteger)size,
	)

	return nil
}

_generate_mipmaps :: proc(cb: Command_Buffer, texture: Texture) -> Result #no_type_assert {
	metadata, metadata_ok := hm.get(&_command_buffers, cb)
	if !metadata_ok {
		return .Invalid_Command_Buffer
	}

	texture_metadata, texture_ok := hm.get(&_textures, texture)
	if !texture_ok {
		return .Invalid_Texture
	}

	_ensure_valid_blit_encoder(metadata)
	metadata.blit_encoder->generateMipmapsForTexture(texture_metadata.texture)

	return nil
}

_barrier :: proc(cb: Command_Buffer, before: Stages, after: Stages) -> Result {
	metadata, metadata_ok := hm.get(&_command_buffers, cb)
	if !metadata_ok {
		return .Invalid_Command_Buffer
	}

	// In Metal 3:
	// 	- Commands inside an encoder are executed in order (except for compute encoders with .Concurrent
	// 		dispatch type).
	// 	- Encoders are executed in order.
	// So the only effective buffer to think about is the compute->compute one.
	if metadata.current_encoding == .Compute {
		if .Compute in before && .Compute in after {
			_flush_compute_encoder(metadata)
		}
	}

	return nil
}

_set_pipeline :: proc(cb: Command_Buffer, pipeline: Pipeline) -> Result {
	metadata, metadata_ok := hm.get(&_command_buffers, cb)
	if !metadata_ok {
		return .Invalid_Command_Buffer
	}

	metadata.pipeline = pipeline

	return nil
}

_set_indirect_buffer_pool :: proc(cb: Command_Buffer, buffers: []Buffer) -> Result {
	metadata, metadata_ok := hm.get(&_command_buffers, cb)
	if !metadata_ok {
		return .Invalid_Command_Buffer
	}

	metadata.accessed_heaps = make([]^MTL.Heap, len(buffers))

	for buffer, i in buffers {
		buffer_metadata, buffer_ok := hm.get(&_buffers, buffer.handle)
		if !buffer_ok {
			return .Invalid_Buffer
		}
		
		metadata.accessed_heaps[i] = buffer_metadata.heap
	}

	return nil
}

_set_texture_pool :: proc(cb: Command_Buffer, textures: []View) -> Result {
	metadata, metadata_ok := hm.get(&_command_buffers, cb)
	if !metadata_ok {
		return .Invalid_Command_Buffer
	}

	metadata.texture_heap = make([]MTL.ResourceID, len(textures))
	for view, i in textures {
		view_metadata, view_ok := hm.get(&_views, view)
		if !view_ok {
			return .Invalid_View
		}

		metadata.texture_heap[i] = view_metadata.view->gpuResourceID()
	}

	return nil
}

_set_buffer :: proc(cb: Command_Buffer, buffer: Buffer, index: int, stage: Raster_Stage = .Compute) -> Result {
	metadata, metadata_ok := hm.get(&_command_buffers, cb)
	if !metadata_ok {
		return .Invalid_Command_Buffer
	}

	buffer_metadata, buffer_ok := hm.get(&_buffers, buffer.handle)
	if !buffer_ok {
		return .Invalid_Buffer
	}
	
	offset := _offset_from_base(buffer, buffer_metadata)

	metadata.buffers[stage][index] = {
		heap	= buffer_metadata.heap,
		buffer	= buffer_metadata.buffer,
		offset	= offset,
	}

	return nil
}

_dispatch :: proc(cb: Command_Buffer, thread_count: [3]int) -> Result {
	metadata, metadata_ok := hm.get(&_command_buffers, cb)
	if !metadata_ok {
		return .Invalid_Command_Buffer
	}

	pipeline_metadata, pipeline_ok := hm.get(&_pipelines, metadata.pipeline)
	if !pipeline_ok {
		return .Invalid_Pipeline
	}

	pso, is_pso := pipeline_metadata.pipeline.(^MTL.ComputePipelineState)
	if !is_pso {
		return .Incompatible_Pipeline
	}

	_ensure_valid_compute_encoder(metadata)
	metadata.compute_encoder->useHeaps(metadata.accessed_heaps)
	metadata.compute_encoder->setBytes(mem.slice_to_bytes(metadata.texture_heap), 8)
	for buffer, i in metadata.buffers[.Compute] {
		metadata.compute_encoder->setBuffer(buffer.buffer, cast(NS.UInteger)buffer.offset, cast(NS.UInteger)i)
	}
	metadata.compute_encoder->setComputePipelineState(pso)
	metadata.compute_encoder->dispatchThreads(
		{
			cast(NS.Integer)thread_count.x,
			cast(NS.Integer)thread_count.y,
			cast(NS.Integer)thread_count.z,
		},
		{
			cast(NS.Integer)pipeline_metadata.group_size.x,
			cast(NS.Integer)pipeline_metadata.group_size.y,
			cast(NS.Integer)pipeline_metadata.group_size.z,
		},
	)

	return nil
}

_submit :: proc(cb: Command_Buffer) -> Result {
	metadata, metadata_ok := hm.get(&_command_buffers, cb)
	if !metadata_ok {
		return .Invalid_Command_Buffer
	}

	_flush_blit_encoder(metadata)
	_flush_compute_encoder(metadata)

	metadata.command_buffer->commit()

	return nil
}

_flush_current_encoder :: proc(cb: ^_Command_Buffer_Metadata) {
	switch cb.current_encoding {
	case .None:
	case .Blit:
		cb.blit_encoder->endEncoding()
		cb.blit_encoder = nil
	case .Compute:
		cb.compute_encoder->endEncoding()
		cb.compute_encoder = nil
	case .Render:
		cb.render_encoder->endEncoding()
		cb.render_encoder = nil
	}
}

_ensure_valid_blit_encoder :: proc(cb: ^_Command_Buffer_Metadata) {
	if cb.command_buffer == nil {
		cb.command_buffer = _queue->commandBuffer()
	}

	if cb.current_encoding != .Blit {
		_flush_current_encoder(cb)
		cb.current_encoding = .Blit
	}

	if cb.blit_encoder == nil {
		cb.blit_encoder = cb.command_buffer->blitCommandEncoder()
	}
}

_flush_blit_encoder :: proc(cb: ^_Command_Buffer_Metadata) {
	if cb.blit_encoder == nil {
		return
	}

	if cb.current_encoding != .Blit {
		return
	}

	cb.blit_encoder->endEncoding()
	cb.blit_encoder = nil
}

_ensure_valid_compute_encoder :: proc(cb: ^_Command_Buffer_Metadata) {
	if cb.command_buffer == nil {
		cb.command_buffer = _queue->commandBuffer()
	}

	if cb.current_encoding != .Compute {
		_flush_current_encoder(cb)
		cb.current_encoding = .Compute
	}

	if cb.compute_encoder == nil {
		cb.compute_encoder = cb.command_buffer->computeCommandEncoderWithDispatchType(.Concurrent)
	}
}

_flush_compute_encoder :: proc(cb: ^_Command_Buffer_Metadata) {
	if cb.compute_encoder == nil {
		return
	}

	if cb.current_encoding != .Compute {
		return
	}

	cb.compute_encoder->endEncoding()
	cb.compute_encoder = nil
}

