package vicixdev_gfx

import "base:runtime"
import "core:sync"
import hm "core:container/handle_map"

Sampler :: distinct Handle

Filter :: enum {
	Nearest,
	Linear,
}

Address_Mode :: enum {
	Repeat,
	Mirrored_Repeat,
	Clamp_To_Edge,
	Clamp_To_Border,
}

Border_Color :: enum {
	Transparent_Black_Float,
	Transparent_Black_Int,
	Opaque_Black_Float,
	Opaque_Black_Int,
	Opaque_White_Float,
	Opaque_White_Int,
}

Sampler_Descriptor :: struct {
	min_filter:	Filter,
	mag_filter:	Filter,
	mip_filter:	Filter,

	address_u:	Address_Mode,
	address_v:	Address_Mode,
	address_w:	Address_Mode,

	border_color:	Border_Color,

	max_anisotropy:	int,
}

_Sampler_Metadata :: struct {
	handle:		Sampler,
	using desc:	Sampler_Descriptor,

	using platform: struct #raw_union {
		vk:	vk_Sampler_Metadata,
		m3:	m3_Sampler_Metadata,
	},
}

_samplers:		hm.Dynamic_Handle_Map(_Sampler_Metadata, Sampler)
_samplers_mutex:	sync.RW_Mutex

create_sampler :: proc(descriptor: Sampler_Descriptor, location := #caller_location) -> (sampler: Sampler, res: Result) {
	_check_device_selected(location) or_return

	handle, metadata := _add_sampler_metadata() or_return
	defer if res != nil do _remove_sampler_metadata(handle)

	metadata.desc = descriptor

	when TARGET_API == .Vulkan {
		vk_create_sampler(metadata, descriptor) or_return
	} else when TARGET_API == .Metal_3 {
		m3_create_sampler(metadata, descriptor) or_return
	}

	return handle, nil
}

destroy_sampler :: proc(sampler: Sampler, location := #caller_location) {
	if _check_device_selected(location) != nil {
		return
	}

	metadata, metadata_res := _metadata_of(sampler)
	_check_sampler_handle(metadata_res, sampler, location)
	if metadata_res != nil {
		return
	}

	when TARGET_API == .Vulkan {
		vk_destroy_sampler(metadata)
	} else when TARGET_API == .Metal_3 {
		m3_destroy_sampler(metadata)
	}

	_remove_sampler_metadata(sampler)
}

label_sampler :: proc(sampler: Sampler, label: string, location := #caller_location) {
	if _check_device_selected(location) != nil do return

	metadata, metadata_res := _metadata_of(sampler)
	_check_sampler_handle(metadata_res, sampler, location)
	if metadata_res != nil {
		return
	}

	res: Result
	when TARGET_API == .Vulkan {
		res = vk_label_sampler(metadata, label)
	} else when TARGET_API == .Metal_3 {
		res = m3_label_sampler(metadata, label)
	}

	_check_generic_backend_error(res, location)
}

_check_sampler_handle :: proc(result: Result, sampler: Sampler, location: runtime.Source_Code_Location) -> Result {
	_check_result(
		result,
		.Warning,
		"Invalid resource handle",
		"Invalid sampler handle (%v).",
		sampler,
		location=location,
	) or_return
	return nil
}

_sampler_metadata_of :: proc(sampler: Sampler) -> (^_Sampler_Metadata, Result) {
	sync.shared_guard(&_samplers_mutex)

	metadata, ok := hm.get(&_samplers, sampler)
	if !ok {
		return nil, .Invalid_Sampler
	}
	
	return metadata, nil
}

_add_sampler_metadata :: proc() -> (sampler: Sampler, metadata: ^_Sampler_Metadata, res: Result) {
	sync.guard(&_samplers_mutex)

	sampler = hm.add(&_samplers, _Sampler_Metadata {}) or_return
	metadata = hm.get(&_samplers, sampler)

	return
}

_remove_sampler_metadata :: proc(sampler: Sampler) {
	sync.guard(&_samplers_mutex)

	hm.remove(&_samplers, sampler)
}

