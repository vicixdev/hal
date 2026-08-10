package gfx

import "base:runtime"
import "core:slice"
import hm "core:container/handle_map"

Resource_Set :: distinct Handle

_Resource_Set_Metadata :: struct {
	handle:			Resource_Set,

	texture_sets:		[Texture_Type][]View,
	storage_texture_sets:	[Texture_Type][]View,
	sampler_set:		[]Sampler,

	using platform: struct #raw_union {
		vk:	vk_Resource_Set_Metadata,
		m3:	m3_Resource_Set_Metadata,
	},
}

_resource_sets: hm.Dynamic_Handle_Map(_Resource_Set_Metadata, Resource_Set)

create_resource_set :: proc(location := #caller_location) -> (set: Resource_Set, res: Result) {
	
	_check_device_selected(location) or_return

	handle, metadata := _add_resource_set_metadata() or_return

	when TARGET_API == .Vulkan {
		res = vk_create_resource_set(metadata)
	} else when TARGET_API == .Metal_3 {
		res = m3_create_resource_set(metadata)
	}

	_check_generic_backend_error(res, location) or_return

	return handle, nil
}

destroy_resource_set :: proc(resource_set: Resource_Set, location := #caller_location) {
	metadata, metadata_res := _metadata_of(resource_set)
	_check_resource_set_handle(metadata_res, resource_set, location)
	if metadata_res != nil do return

	when TARGET_API == .Vulkan {
		vk_destroy_resource_set(metadata)
	} else when TARGET_API == .Metal_3 {
		m3_destroy_resource_set(metadata)
	}

	delete(metadata.sampler_set, _generic_allocator)
	for set in metadata.texture_sets {
		delete(set, _generic_allocator)
	}
	for set in metadata.storage_texture_sets {
		delete(set, _generic_allocator)
	}

	_remove_resource_set_metadata(resource_set)
}

set_texture_set :: proc(
	resource_set: Resource_Set,
	type: Texture_Type,
	textures: []View,
	location := #caller_location,
) {

	metadata, metadata_res := _metadata_of(resource_set)
	_check_resource_set_handle(metadata_res, resource_set, location)
	if metadata_res != nil do return

	for view, i in textures {
		view_metadata, view_metadata_res := _metadata_of(view)
		_check_view_handle(view_metadata_res, view, location)
		if view_metadata_res != nil do return

		texture_metadata, texture_metatadata_res := _metadata_of(view_metadata.texture)
		assert(
			texture_metatadata_res == nil,
			"If the view metadata exists, then the referenced texture metadata should also exist.",
		)

		if view_metadata.type != type {
			_log_message(
				.Invalid_Texture,
				.Error,
				"Invalid texture type",
				"Only views with type %v are allowed in the texture set of type %v. The view %v " +
				"(at index %d) is of type %v.",
				type,
				type,
				view,
				i,
				view_metadata.type,
				location=location,
			)
			return
		}

		if .Sampled not_in texture_metadata.usage {
			_log_message(
				.Invalid_Texture,
				.Error,
				"Invalid texture usage",
				"A texture, in order to be used in a texture set should, be created with the `.Sampled` " +
				"usage. The provided view %v (at index %i) references a texture with usage %v.",
				view,
				i,
				texture_metadata.usage,
				location=location,
			)
			return
		}
	}
	
	delete(metadata.texture_sets[type], _generic_allocator)
	metadata.texture_sets[type] = slice.clone(textures, _generic_allocator)

	res: Result
	when TARGET_API == .Vulkan {
		res = vk_set_texture_set(metadata, type)
	} else when TARGET_API == .Metal_3 {
		res = m3_set_texture_set(metadata, type)
	}

	_check_generic_backend_error(res, location)
}

set_storage_texture_set :: proc(
	resource_set: Resource_Set,
	type: Texture_Type,
	textures: []View,
	location := #caller_location,
) {

	metadata, metadata_res := _metadata_of(resource_set)
	_check_resource_set_handle(metadata_res, resource_set, location)
	if metadata_res != nil do return

	for view, i in textures {
		view_metadata, view_metadata_res := _metadata_of(view)
		_check_view_handle(view_metadata_res, view, location)
		if view_metadata_res != nil do return

		texture_metadata, texture_metatadata_res := _metadata_of(view_metadata.texture)
		assert(
			texture_metatadata_res == nil,
			"If the view metadata exists, then the referenced texture metadata should also exist.",
		)

		if view_metadata.type != type {
			_log_message(
				.Invalid_Texture,
				.Error,
				"Invalid texture type",
				"Only views with type %v are allowed in the texture set of type %v. The view %v " +
				"(at index %d) is of type %v.",
				type,
				type,
				view,
				i,
				view_metadata.type,
				location=location,
			)
			return
		}

		if .Storage not_in texture_metadata.usage {
			_log_message(
				.Invalid_Texture,
				.Error,
				"Invalid texture usage",
				"A texture, in order to be used in a texture set should, be created with the " +
				"`.Storage` usage. The provided view %v (at index %d) references a texture with " +
				"usage %v.",
				view,
				i,
				texture_metadata.usage,
				location=location,
			)
			return
		}
	}

	delete(metadata.storage_texture_sets[type], _generic_allocator)
	metadata.storage_texture_sets[type] = slice.clone(textures, _generic_allocator)
	
	res: Result
	when TARGET_API == .Vulkan {
		res = vk_set_storage_texture_set(metadata, type)
	} else when TARGET_API == .Metal_3 {
		res = m3_set_storage_texture_set(metadata, type)
	}

	_check_generic_backend_error(res, location)
}

set_sampler_set :: proc(resource_set: Resource_Set, samplers: []Sampler, location := #caller_location) {
	metadata, metadata_res := _metadata_of(resource_set)
	_check_resource_set_handle(metadata_res, resource_set, location)
	if metadata_res != nil do return

	for sampler in samplers {
		_, sampler_metadata_res := _metadata_of(sampler)
		_check_sampler_handle(sampler_metadata_res, sampler, location)
		if sampler_metadata_res != nil do return
	}

	delete(metadata.sampler_set, _generic_allocator)
	metadata.sampler_set = slice.clone(samplers, _generic_allocator)
	
	res: Result
	when TARGET_API == .Vulkan {
		res = vk_set_sampler_set(metadata)
	} else when TARGET_API == .Metal_3 {
		res = m3_set_sampler_set(metadata)
	}

	_check_generic_backend_error(res, location)
}

_check_resource_set_handle :: proc(result: Result, resource_set: Resource_Set, location: runtime.Source_Code_Location) -> Result {
	_check_result(
		result,
		.Warning,
		"Invalid resource handle",
		"Invalid resource set handle (%v).",
		resource_set,
		location=location,
	) or_return
	return nil
}

_resource_set_metadata_of :: proc(resource_set: Resource_Set) -> (^_Resource_Set_Metadata, Result) {
	metadata, ok := hm.get(&_resource_sets, resource_set)
	if !ok {
		return nil, .Invalid_Resource_Set
	}
	
	return metadata, nil
}

_add_resource_set_metadata :: proc() -> (resource_set: Resource_Set, metadata: ^_Resource_Set_Metadata, res: Result) {
	resource_set = hm.add(&_resource_sets, _Resource_Set_Metadata {}) or_return
	metadata = hm.get(&_resource_sets, resource_set)

	return
}

_remove_resource_set_metadata :: proc(resource_set: Resource_Set) {
	hm.remove(&_resource_sets, resource_set)
}

