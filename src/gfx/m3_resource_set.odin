#+build darwin
package vicixdev_gfx

import NS "core:sys/darwin/Foundation"
import MTL "vendor:darwin/Metal"

// NOTE: Gpu repr
m3_Resource_Set_Root :: struct #align(16) {
	sampler_set:		u64,
	texture_sets:		[View_Type]u64,
	storage_texture_sets:	[Storage_View_Type]u64,
	_pad:			u64,
}
#assert(size_of(m3_Resource_Set_Root) == 96)

m3_Resource_Set_Metadata :: struct {
	texture_sets:		[View_Type]^MTL.Buffer,
	storage_texture_sets:	[Storage_View_Type]^MTL.Buffer,
	sampler_set:		^MTL.Buffer,

	root_buffer:		^MTL.Buffer,
	root:			^m3_Resource_Set_Root,
}

m3_create_resource_set :: proc(metadata: ^_Resource_Set_Metadata) -> Result {
	NS.scoped_autoreleasepool()
	
	root_buffer := m3_resource_set_heap->newBufferWithLength(
		size_of(m3_Resource_Set_Root),
		{ .CPUCacheModeWriteCombined, .HazardTrackingModeUntracked },
	)
	if root_buffer == nil {
		return .Out_Of_Gpu_Memory
	}

	root := root_buffer->contentsAsType(m3_Resource_Set_Root)
	root^ = {}

	metadata.m3.root_buffer = root_buffer
	metadata.m3.root = root

	return nil
}

m3_destroy_resource_set :: proc(metadata: ^_Resource_Set_Metadata) -> Result {
	NS.scoped_autoreleasepool()
	
	for texture_set in metadata.m3.texture_sets {
		if texture_set != nil {
			texture_set->release()
		}
	}

	sampler_set := metadata.m3.sampler_set
	if sampler_set != nil {
		sampler_set->release()
	}

	metadata.m3.root_buffer->release()

	return nil
}

m3_set_texture_set :: proc(metadata: ^_Resource_Set_Metadata, type: View_Type) -> Result {
	NS.scoped_autoreleasepool()
	
	textures := metadata.texture_sets[type]

	if metadata.m3.texture_sets[type] != nil {
		metadata.m3.texture_sets[type]->release()
	}

	texture_set := m3_resource_set_heap->newBufferWithLength(
		size_of(MTL.ResourceID) * cast(NS.UInteger)len(textures),
		{ .CPUCacheModeWriteCombined, .HazardTrackingModeUntracked},
	)
	if texture_set == nil {
		return .Out_Of_Gpu_Memory
	}
	
	mtl_textures := texture_set->contentsAsSlice([]MTL.ResourceID)
	for view, i in textures {
		metadata := _metadata_of(view) or_return
		mtl_textures[i] = metadata.m3.view->gpuResourceID()
	}

	metadata.m3.texture_sets[type] = texture_set
	metadata.m3.root.texture_sets[type] = texture_set->gpuAddress()

	return nil
}

m3_set_storage_texture_set :: proc(metadata: ^_Resource_Set_Metadata, type: Storage_View_Type) -> Result {
	NS.scoped_autoreleasepool()
	
	textures := metadata.storage_texture_sets[type]

	if metadata.m3.storage_texture_sets[type] != nil {
		metadata.m3.storage_texture_sets[type]->release()
	}

	texture_set := m3_resource_set_heap->newBufferWithLength(
		size_of(MTL.ResourceID) * cast(NS.UInteger)len(textures),
		{ .CPUCacheModeWriteCombined, .HazardTrackingModeUntracked},
	)
	if texture_set == nil {
		return .Out_Of_Gpu_Memory
	}
	
	mtl_textures := texture_set->contentsAsSlice([]MTL.ResourceID)
	for view, i in textures {
		metadata := _metadata_of(view) or_return
		mtl_textures[i] = metadata.m3.view->gpuResourceID()
	}

	metadata.m3.storage_texture_sets[type] = texture_set
	metadata.m3.root.storage_texture_sets[type] = texture_set->gpuAddress()

	return nil
}

m3_set_sampler_set :: proc(metadata: ^_Resource_Set_Metadata) -> Result {
	NS.scoped_autoreleasepool()
	
	samplers := metadata.sampler_set

	if metadata.m3.sampler_set != nil {
		metadata.m3.sampler_set->release()
	}

	sampler_set := m3_resource_set_heap->newBufferWithLength(
		size_of(MTL.ResourceID) * cast(NS.UInteger)len(samplers),
		{ .CPUCacheModeWriteCombined, .HazardTrackingModeUntracked},
	)
	if sampler_set == nil {
		return .Out_Of_Gpu_Memory
	}
	
	mtl_samplers := sampler_set->contentsAsSlice([]MTL.ResourceID)
	for sampler, i in samplers {
		metadata := _metadata_of(sampler) or_return
		mtl_samplers[i] = metadata.m3.sampler->gpuResourceID()
	}

	metadata.m3.sampler_set = sampler_set
	metadata.m3.root.sampler_set = sampler_set->gpuAddress()

	return nil
}
