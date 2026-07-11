// #+build darwin
package gfx

// import hm "core:container/handle_map"
// import NS "core:sys/darwin/Foundation"
// import MTL "vendor:darwin/Metal"

// _queue:	^MTL.CommandQueue
// _compute_queue:	^MTL.CommandQueue
// _blit_queue:	^MTL.CommandQueue
// _render_queue:	^MTL.CommandQueue

// _submit :: proc(cb: Command_Buffer) -> Result {
// 	NS.scoped_autoreleasepool()

// 	metadata, metadata_ok := hm.get(&_command_buffers, cb)
// 	if !metadata_ok {
// 		return .Invalid_Command_Buffer
// 	}

// 	if (len(metadata.current_passes[.Transfer].data.(_Blit_Pass).commands) > 0) {
// 		append(&metadata.passes, metadata.current_passes[.Transfer])
// 	}

// 	if (len(metadata.current_passes[.Compute].data.(_Compute_Pass).commands) > 0) {
// 		append(&metadata.passes, metadata.current_passes[.Compute])
// 	}

// 	fences := make([]^MTL.Fence, metadata.fence_idx, context.temp_allocator)
// 	for &fence in fences {
// 		fence = _device->newFence()
// 		fence->autorelease()
// 	}

// 	for pass in metadata.passes do switch data in pass.data {
// 	case _Compute_Pass:
// 		compute_cb := _compute_queue->commandBuffer()
// 		compute_en := compute_cb->computeCommandEncoderWithDispatchType(.Concurrent)

// 		for w in pass.wait_for {
// 			compute_en->waitForFence(fences[w])
// 		}

// 		for c in data.commands do switch command in c {}

// 		for s in pass.signal_when_done {
// 			compute_en->updateFence(fences[s])
// 		}

// 		compute_en->endEncoding()
// 		compute_cb->commit()

// 	case _Blit_Pass:
// 		blit_cb := _blit_queue->commandBuffer()
// 		blit_en	:= blit_cb->blitCommandEncoder()

// 		for w in pass.wait_for {
// 			blit_en->waitForFence(fences[w])
// 		}

// 		for c in data.commands do switch command in c {
// 		case _Command_Mem_Copy:
// 			source_metadata, source_ok := hm.get(&_buffers, command.source.handle)
// 			if !source_ok {
// 				return .Invalid_Buffer
// 			}

// 			dest_metadata, dest_ok := hm.get(&_buffers, command.destination.handle)
// 			if !dest_ok {
// 				return .Invalid_Buffer
// 			}

// 			source_offset := _offset_from_base(command.source, source_metadata)
// 			dest_offset := _offset_from_base(command.destination, dest_metadata)

// 			blit_en->copyFromBuffer(
// 				source_metadata.buffer,
// 				cast(NS.UInteger)source_offset,
// 				dest_metadata.buffer,
// 				cast(NS.UInteger)dest_offset,
// 				cast(NS.UInteger)command.size,
// 			)

// 		case _Command_Generate_Mipmaps:
// 			texture_metadata, texture_ok := hm.get(&_textures, command.texture)
// 			if !texture_ok {
// 				return .Invalid_Texture
// 			}

// 			blit_en->generateMipmapsForTexture(texture_metadata.texture)
// 		}

// 		for s in pass.signal_when_done {
// 			blit_en->updateFence(fences[s])
// 		}

// 		blit_en->endEncoding()
// 		blit_cb->commit()

// 	case _Render_Pass:
// 		// render_cb := _compute_queue->commandBuffer()
// 		// render_en := render_cb->renderCommandEncoderWithDescriptor({})

// 		// for w in pass.wait_for {
// 			// render_en->waitForFence(fences[w])
// 		// }

// 		// for c in data.commands do switch command in c {}

// 		// for s in pass.signal_when_done {
// 			// render_en->updateFence(fences[s])
// 		// }
// 	}

// 	return nil
// }

