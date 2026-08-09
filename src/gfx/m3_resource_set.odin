package gfx

import "core:mem"
import MTL "vendor:darwin/Metal"

m3_Resource_Set_Buffer :: struct {
	buffer:	Buffer,
	size:	int,
}

m3_Resource_Set_Metadata :: struct {
	texture_sets:		[Texture_Type]m3_Resource_Set_Buffer,
	storage_texture_sets:	[Texture_Type]m3_Resource_Set_Buffer,
	sampler_set:		m3_Resource_Set_Buffer,
}

m3_create_resource_set :: proc(metadata: ^_Resource_Set_Metadata) -> Result {
	return nil
}

m3_destroy_resource_set :: proc(metadata: ^_Resource_Set_Metadata) -> Result {
	for texture_set in metadata.m3.texture_sets {
		if texture_set.size != 0 {
			dealloc(texture_set.buffer)
		}
	}

	sampler_set := metadata.m3.sampler_set
	if sampler_set.size != 0 {
		dealloc(sampler_set.buffer)
	}

	return nil
}

m3_set_texture_set :: proc(metadata: ^_Resource_Set_Metadata, type: Texture_Type) -> Result {
	views := metadata.texture_sets[type]
	m3_views := &metadata.m3.texture_sets[type]

	required_size := mem.align_forward_int(
		len(views) * size_of(MTL.ResourceID),
		_device_info.limits.allocation_alignment,
	)

	if m3_views.size <= required_size {
		if m3_views.size > 0 do dealloc(m3_views.buffer)

		m3_views.buffer = alloc(.Default, required_size) or_return
		m3_views.size = required_size
	}

	gpu_views := cast([^]MTL.ResourceID)m3_views.buffer.contents
	for view, i in views {
		metadata := _metadata_of(view) or_return
		gpu_views[i] = metadata.m3.view->gpuResourceID()
	}

	return nil
}

m3_set_storage_texture_set :: proc(metadata: ^_Resource_Set_Metadata, type: Texture_Type) -> Result {
	views := metadata.storage_texture_sets[type]
	m3_views := &metadata.m3.storage_texture_sets[type]

	required_size := mem.align_forward_int(
		len(views) * size_of(MTL.ResourceID),
		_device_info.limits.allocation_alignment,
	)

	if m3_views.size <= required_size {
		if m3_views.size > 0 do dealloc(m3_views.buffer)

		m3_views.buffer = alloc(.Default, required_size) or_return
		m3_views.size = required_size
	}

	gpu_views := cast([^]MTL.ResourceID)m3_views.buffer.contents
	for view, i in views {
		metadata := _metadata_of(view) or_return
		gpu_views[i] = metadata.m3.view->gpuResourceID()
	}

	return nil
}

m3_set_sampler_set :: proc(metadata: ^_Resource_Set_Metadata) -> Result {
	samplers := metadata.sampler_set
	m3_samplers := &metadata.m3.sampler_set

	required_size := mem.align_forward_int(
		len(samplers) * size_of(MTL.ResourceID),
		_device_info.limits.allocation_alignment,
	)

	if m3_samplers.size <= required_size {
		if m3_samplers.size > 0 do dealloc(m3_samplers.buffer)

		m3_samplers.buffer = alloc(.Default, required_size) or_return
		m3_samplers.size = required_size
	}

	gpu_samplers := cast([^]MTL.ResourceID)m3_samplers.buffer.contents
	for sampler, i in samplers {
		metadata := _metadata_of(sampler) or_return
		gpu_samplers[i] = metadata.m3.sampler->gpuResourceID()
	}

	return nil
}
