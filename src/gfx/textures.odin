package gfx

import "base:runtime"
import "core:sync"
import hm "core:container/handle_map"

Texture :: distinct Handle
View :: distinct Handle

Texture_Type :: enum {
	D1,
	D2_Array,
	D3,
}

View_Type :: enum {
	D1,
	D2,
	D3,
	Cube,
	D2_Array,
	Cube_Array,
}

Pixel_Format :: enum {
	None,
	R8_Unorm,
	RG8_Unorm,
	RGBA8_Unorm,
	RGBA8_Srgb,
	BGRA8_Unorm,
	BGRA8_Srgb,
	R16_Float,
	RG16_Float,
	RGBA16_Float,
	RGBA16_Unorm,
	R16_Unorm,
	RG16_Unorm,
	R32_Float,
	RG32_Float,
	RGBA32_Float,
	RG11B10_Float,
	RGB10_A2_Unorm,
	RGB10_A2_Uint,
	D32_Float,
	D24_Unorm_S8_Uint,
	D32_Float_S8_Uint,
	D16_Unorm,
}

Texture_Usage :: enum {
	Sampled = 0,
	Storage,
	Color_Attachment,
	Depth_Stencil_Attachment,
}
Texture_Usages :: bit_set[Texture_Usage]

Texture_Descriptor :: struct {
	type:		Texture_Type,
	dimensions:	[3]int,
	mip_count:	int,
	layer_count:	int,
	sample_count:	int,
	format:		Pixel_Format,
	usage:		Texture_Usages,
}

View_Descriptor :: struct {
	type:		View_Type,
	base_mip:	int,
	mip_count:	int,
	base_layer:	int,
	layer_count:	int,
}

Texture_Region :: struct {
	base_layer:	int,
	layer_count:	int,
	mip:		int,
	origin:		[3]int,
	size:		[3]int,
}

_View_Reference :: union {
	Texture,
	Surface,
}

_Texture_Metadata :: struct {
	handle:			Texture,
	using desc:		Texture_Descriptor,

	cube_compatible:	bool,

	default_view:		View,

	using platform:	struct #raw_union {
		m3:		m3_Texture_Metadata,
		vk:		vk_Texture_Metadata,
	},
}

_View_Metadata :: struct {
	handle:		View,
	using desc:	View_Descriptor,

	// texture:	Texture,
	reference:	_View_Reference,
	next_view:	View,

	// If the view is referencing a texture, it can be used only be used once as a render target.
	// This flags indicates if the surface-referencing view has already been used as a render target.
	// ATOMIC
	used:		bool,

	using platform: struct #raw_union {
		m3:	m3_View_Metadata,
		vk:	vk_View_Metadata,
	},
}

_textures:		hm.Dynamic_Handle_Map(_Texture_Metadata, Texture)
_textures_mutex:	sync.RW_Mutex
_views:			hm.Dynamic_Handle_Map(_View_Metadata, View)
_views_mutex:		sync.RW_Mutex

size_align_of :: proc(
	descriptor: Texture_Descriptor,
	location := #caller_location,
) -> (size: int, align: int, res: Result) {

	descriptor := descriptor
	_normalize_texture_descriptor(&descriptor)

	_check_device_selected(location) or_return
	_check_texture_descriptor(descriptor, location) or_return

	when TARGET_API == .Vulkan {
		return vk_size_align_of(descriptor)
	} else when TARGET_API == .Metal_3 {
		return m3_size_align_of(descriptor)
	}
}

create_texture :: proc(
	buffer:		Buffer,
	descriptor:	Texture_Descriptor,
	location	:= #caller_location
) -> (
	handle: Texture,
	res: Result,
) {
	descriptor := descriptor
	_normalize_texture_descriptor(&descriptor)

	_check_device_selected(location) or_return

	// NOTE: size_align_of() also checks for the descriptor validity.
	required_size, required_align := size_align_of(descriptor, location) or_return

	buffer_metadata, buffer_metadata_res := _metadata_of(buffer)
	_check_buffer_handle(buffer_metadata_res, buffer, location) or_return

	offset_from_base := _offset_from_base(buffer, buffer_metadata)
	free_space := buffer_metadata.size - cast(int)_offset_from_base(buffer, buffer_metadata)

	_check_condition(
		_is_aligned(buffer.address, required_align),
		.Invalid_Align,
		.Error,
		"Invalid align",
		"The provided buffer address (0x%x) is not aligned with the required texture aligments for the " +
		"provided descriptor (required alignment: %d bytes)",
		buffer.address,
		required_align,
		location=location,
	) or_return
	_check_condition(
		free_space >= required_size,
		.Out_Of_Gpu_Memory,
		.Error,
		"Not enough memory",
		"The buffer is not big enough to contain the requested texture at the offset %d (%d available bytes, " +
		"%d requested bytes).",
		offset_from_base,
		free_space,
		required_size,
		location=location,
	) or_return
	_check_condition(
		buffer_metadata.memory_type == .Private,
		.Incompatible_Memory_Type,
		.Error,
		"Incompatible memory type",
		"Textures can only be allocated in Private memory. The specified buffer is %v memory.",
		buffer_metadata.memory_type,
		location=location,
	) or_return

	texture, metadata := _add_texture_metadata() or_return
	defer if res != nil do _remove_texture_metadata(texture)

	view, view_metadata := _add_view_metadata() or_return
	defer if res != nil do _remove_view_metadata(view)

	metadata.desc		= descriptor
	metadata.cube_compatible = _is_cube_compatible(descriptor)

	view_metadata.mip_count		= metadata.mip_count
	view_metadata.layer_count	= metadata.layer_count
	view_metadata.type		= _texture_type_to_view_type(descriptor)

	metadata.default_view	= view
	view_metadata.next_view	= view
	view_metadata.reference	= texture

	when TARGET_API == .Vulkan {
		res = vk_create_texture(metadata, buffer, buffer_metadata, view_metadata, descriptor)
	} else when TARGET_API == .Metal_3 {
		res = m3_create_texture(metadata, buffer, buffer_metadata, view_metadata, descriptor)
	}

	_check_specific_result(
		res,
		.Out_Of_Gpu_Memory,
		.Warning,
		"Out of GPU memory",
		"Could not allocate texture with descriptor %#v: not enough free GPU memory.",
		descriptor,
		location=location,
	) or_return
	_check_generic_backend_error(res, location) or_return

	return texture, nil
}

destroy_texture :: proc(texture: Texture, location := #caller_location) {
	if _check_device_selected(location) != nil {
		return
	}

	metadata, res := _metadata_of(texture)
	_check_texture_handle(res, texture, location)
	if res != nil {
		return
	}

	start_view	:= metadata.default_view
	current_view	:= metadata.default_view
	for {
		view_metadata, view_res := _metadata_of(current_view)
		assert(view_res == nil, "Could not find a view of a texture. Broken view chain?")

		next_view := view_metadata.next_view

		when TARGET_API == .Vulkan {
			vk_destroy_view(view_metadata)
		} else when TARGET_API == .Metal_3 {
			m3_destroy_view(view_metadata)
		}

		_remove_view_metadata(current_view)

		current_view = next_view
		if current_view == start_view {
			break
		}
	}

	when TARGET_API == .Vulkan {
		vk_destroy_texture(metadata)
	} else when TARGET_API == .Metal_3 {
		m3_destroy_texture(metadata)
	}

	_remove_texture_metadata(texture)
}

label_texture :: proc(texture: Texture, label: string, location := #caller_location) {
	if _check_device_selected(location) != nil do return

	metadata, metadata_res := _metadata_of(texture)
	_check_texture_handle(metadata_res, texture, location)
	if metadata_res != nil {
		return
	}

	res: Result
	when TARGET_API == .Vulkan {
		res = vk_label_texture(metadata, label)
	} else when TARGET_API == .Metal_3 {
		res = m3_label_texture(metadata, label)
	}

	_check_generic_backend_error(res, location)
}

default_view_of :: proc(texture: Texture, location := #caller_location) -> (view: View, res: Result) {
	_check_device_selected(location) or_return

	metadata, metadata_res := _metadata_of(texture)
	_check_texture_handle(metadata_res, texture, location) or_return

	return metadata.default_view, nil
}

create_view :: proc(
	texture: Texture,
	descriptor: View_Descriptor,
	location := #caller_location,
) -> (view: View, res: Result) {

	descriptor := descriptor
	_normalize_view_descriptor(&descriptor)

	_check_device_selected(location) or_return

	texture_metadata, texture_metadata_res := _metadata_of(texture)
	_check_texture_handle(texture_metadata_res, texture, location) or_return

	_check_view_descriptor(descriptor, texture_metadata^, location) or_return

	default_view_metadata, default_view_err := _metadata_of(texture_metadata.default_view)
	assert(default_view_err == nil, "Could not find the default view of a texture. Broken view chain?")

	handle, metadata := _add_view_metadata() or_return
	defer if res != nil do _remove_view_metadata(handle)

	metadata.desc = descriptor

	metadata.reference	= texture
	metadata.next_view	= default_view_metadata.next_view
	default_view_metadata.next_view = handle

	when TARGET_API == .Vulkan {
		res = vk_create_view_with_descriptor(metadata, texture_metadata, descriptor)
	} else when TARGET_API == .Metal_3 {
		res = m3_create_view_with_descriptor(metadata, texture_metadata, descriptor)
	}

	_check_specific_result(
		res,
		.Out_Of_Gpu_Memory,
		.Warning,
		"Out of GPU memory",
		"Could not allocate a view with descriptor %#v: not enough free GPU memory.",
		descriptor,
		location=location,
	) or_return
	_check_generic_backend_error(res, location) or_return

	return handle, nil
}

label_view :: proc(view: View, label: string, location := #caller_location) {
	if _check_device_selected(location) != nil do return

	metadata, metadata_res := _metadata_of(view)
	_check_view_handle(metadata_res, view, location)
	if metadata_res != nil {
		return
	}

	res: Result
	when TARGET_API == .Vulkan {
		res = vk_label_view(metadata, label)
	} else when TARGET_API == .Metal_3 {
		res = m3_label_view(metadata, label)
	}

	_check_generic_backend_error(res, location)
}

_is_cube_compatible :: proc(descriptor: Texture_Descriptor) -> bool {
	return descriptor.type == .D2_Array &&
		descriptor.layer_count >= 6 &&
		descriptor.dimensions.x == descriptor.dimensions.y
}

_check_texture_region :: proc(
	metadata:	^_Texture_Metadata,
	region:		Texture_Region,
	location:	runtime.Source_Code_Location,
) -> Result {
	
	_check_condition(
		region.origin.x >= 0 && region.origin.y >= 0 && region.origin.z >= 0,
		.Invalid_Arguments,
		.Error,
		"Invalid texture origin",
		"The texture origin dimensions must be positive. Got %v.",
		region.origin,
		location=location,
	) or_return

	_check_condition(
		_impl(metadata.type == .D1, region.size.x > 0 && region.size.yz == { 1, 1 }),
		.Invalid_Arguments,
		.Error,
		"Invalid texture region",
		"If the texture type is `.D1`, then the x region size must be positive and the y and z region sizes " +
		"must be 1. Got %v.",
		region.size,
		location=location,
	) or_return
	_check_condition(
		_impl(metadata.type == .D2_Array, region.size.x > 0 && region.size.y > 0 && region.size.z == 1),
		.Invalid_Arguments,
		.Error,
		"Invalid texture region",
		"If the texture type is `.D2`, the the x and y region sizes must be positive and the z region size " +
		"must be 1. Got %v.",
		region.size,
		location=location,
	) or_return
	_check_condition(
		_impl(metadata.type == .D3, region.size.x > 0 && region.size.y > 0 && region.size.z > 0),
		.Invalid_Arguments,
		.Error,
		"Invalid texture region",
		"If the texture type is `.D3`, the x, y and z region sizes must be positive. Got %v.",
		region.size,
		location=location,
	) or_return

	_check_condition(
		_impl(metadata.type == .D1, region.base_layer == 0 && region.layer_count == 1),
		.Invalid_Arguments,
		.Error,
		"Invalid texture region",
		"If the texture type is `.D1`, then the base layer must be 0 and the layer count must be 1. Found " +
		"base layer %v and layer count %v.",
		region.base_layer,
		region.layer_count,
		location=location,
	) or_return
	_check_condition(
		_impl(metadata.type == .D3, region.base_layer == 0 && region.layer_count == 1),
		.Invalid_Arguments,
		.Error,
		"Invalid texture region",
		"If the texture type is `.D3`, then the base layer must be 0 and the layer count must be 1. Found " +
		"base layer %v and layer count %v.",
		region.base_layer,
		region.layer_count,
		location=location,
	) or_return

	_check_condition(
		metadata.mip_count > region.mip,
		.Invalid_Arguments,
		.Error,
		"Invalid base mipmap level",
		"Out of bounds mipmap access: requested mipmap level %v while for a texture with %v levels.",
		region.mip,
		metadata.mip_count,
		location=location,
	) or_return
	_check_condition(
		region.base_layer + region.layer_count - 1 < metadata.layer_count,
		.Invalid_Descriptor,
		.Error,
		"Invalid base layer",
		"Out of bounds layer access: requested layers [%d-%d] for a texture with %d layers.",
		region.base_layer,
		region.base_layer + region.layer_count,
		metadata.layer_count,
		location=location,
	) or_return

	dimensions := _size_of_mipmap_level(metadata, region.mip)
	dimensions -= region.origin
	_check_condition(
		region.size.x >= dimensions.x && region.size.y >= dimensions.y && region.size.z >= dimensions.z,
		.Invalid_Arguments,
		.Error,
		"Out of bounds image copy",
		"Out of bounds image copy: a copy with origin %v and size %v cannot be issued in a texture with " +
		"dimensions %v.",
		region.origin,
		region.size,
		metadata.dimensions,
		location=location,
	) or_return

	return nil
}

_normalize_texture_descriptor :: proc(descriptor: ^Texture_Descriptor) {
	if descriptor.mip_count == 0 {
		descriptor.mip_count = 1
	}
	if descriptor.layer_count == 0 {
		descriptor.layer_count = 1
	}
	if descriptor.sample_count == 0 {
		descriptor.sample_count = 1
	}
	if descriptor.type == .D1 && descriptor.dimensions.y == 0 {
		descriptor.dimensions.y = 1
	}
	if (descriptor.type == .D2_Array || descriptor.type == .D1) && descriptor.dimensions.z == 0 {
		descriptor.dimensions.z = 1
	}
}

_normalize_view_descriptor :: proc(descriptor: ^View_Descriptor) {
	if descriptor.mip_count == 0 {
		descriptor.mip_count = 1
	}
	if descriptor.layer_count == 0 {
		descriptor.layer_count = 1
	}
}

_check_texture_handle :: proc(result: Result, texture: Texture, location: runtime.Source_Code_Location) -> Result {
	_check_result(
		result,
		.Warning,
		"Invalid resource handle",
		"Invalid texture handle (%v).",
		texture,
		location=location,
	) or_return
	return nil
}

_texture_metadata_of :: proc(texture: Texture) -> (^_Texture_Metadata, Result) {
	sync.shared_guard(&_textures_mutex)

	metadata, ok := hm.get(&_textures, texture)
	if !ok {
		return nil, .Invalid_Texture
	}
	
	return metadata, nil
}

_check_texture_descriptor :: proc(descriptor: Texture_Descriptor, location: runtime.Source_Code_Location) -> Result {
	_check_condition(
		_impl(descriptor.type == .D1, descriptor.dimensions.z > 0 && descriptor.dimensions.yz == { 1, 1 }),
		.Invalid_Descriptor,
		.Error,
		"Invalid dimensions",
		"If the texture type is `.D1`, then the x dimension should be positive and the yz dimensions should " +
		"be 1. (%v found).",
		descriptor.dimensions,
		location=location,
	) or_return
	_check_condition(
		_impl(descriptor.type == .D2_Array,
			descriptor.dimensions.x > 0 && descriptor.dimensions.y > 0 && descriptor.dimensions.z == 1),
		.Invalid_Descriptor,
		.Error,
		"Invalid dimensions",
		"If the texture type is `.D2`, then the x and y dimensions should be positive and the z dimension " +
		"should be 1. (%v found).",
		descriptor.dimensions,
		location=location,
	) or_return
	_check_condition(
		_impl(descriptor.type == .D3,
			descriptor.dimensions.x > 0 && descriptor.dimensions.y > 0 && descriptor.dimensions.z > 0),
		.Invalid_Descriptor,
		.Error,
		"Invalid dimensions",
		"If the texture type is `.D3`, then the x, y and z dimensions should be positive. (%v found).",
		descriptor.dimensions,
		location=location,
	) or_return

	_check_condition(
		_impl(descriptor.type == .D1 || descriptor.type == .D3,
			descriptor.layer_count == 1),
		.Invalid_Descriptor,
		.Error,
		"Invalid layer count",
		"If the texture type is `.D1`, or `.D3`, then the layer count should be exactly 1. (%v found).",
		descriptor.layer_count,
		location=location,
	) or_return
	_check_condition(
		descriptor.layer_count > 0,
		.Invalid_Descriptor,
		.Error,
		"Invalid layer count",
		"Then the layer count should be positive. (%v found).",
		descriptor.layer_count,
		location=location,
	) or_return

	return nil
}

_check_view_descriptor :: proc(
	descriptor:		View_Descriptor,
	texture_descriptor:	_Texture_Metadata,
	location:		runtime.Source_Code_Location,
) -> Result {

	_check_condition(
		_impl(texture_descriptor.type == .D1, descriptor.type == .D1),
		.Invalid_Descriptor,
		.Error,
		"Invalid view type",
		"If the texture type is `.D1`, then the view must also be of type `.D1`. (%v found).",
		descriptor.type,
		location=location,
	) or_return
	_check_condition(
		_impl(texture_descriptor.type == .D2_Array,
			descriptor.type == .D2 ||
			descriptor.type == .D2_Array ||
			descriptor.type == .Cube ||
			descriptor.type == .Cube_Array,
		),
		.Invalid_Descriptor,
		.Error,
		"Invalid view type",
		"If the texture type is `.D2`, then the view must be of type `.D2`, `.D2_Array`, `.Cube` or " +
		"`.Cube_Array`. (%v found).",
		descriptor.type,
		location=location,
	) or_return
	_check_condition(
		_impl(texture_descriptor.type == .D3, descriptor.type == .D3),
		.Invalid_Descriptor,
		.Error,
		"Invalid view type",
		"If the texture type is `.D3`, then the view must also be of type `.D3`. (%v found).",
		descriptor.type,
		location=location,
	) or_return

	_check_condition(
		_impl(descriptor.type == .D1 || descriptor.type == .D2 || descriptor.type == .D3,
			descriptor.layer_count == 1),
		.Invalid_Descriptor,
		.Error,
		"Invalid layer count",
		"If the texture type is `.D1`, `.D2` or `.D3`, then the layer count must be 1. (%d found).",
		descriptor.layer_count,
		location=location,
	) or_return
	_check_condition(
		_impl(descriptor.type == .Cube, descriptor.layer_count == 6),
		.Invalid_Descriptor,
		.Error,
		"Invalid layer count",
		"If the texture type is `.Cube`, then the layer count must be exactly 6. (%d found).",
		descriptor.layer_count,
		location=location,
	) or_return
	_check_condition(
		_impl(descriptor.type == .Cube_Array, descriptor.layer_count % 6 == 0),
		.Invalid_Descriptor,
		.Error,
		"Invalid layer count",
		"If the texture type is `.Cube_Array`, then the layer count must be a multiple of 6. (%d found).",
		descriptor.layer_count,
		location=location,
	) or_return

	_check_condition(
		descriptor.base_layer >= 0 && descriptor.layer_count >= 0,
		.Invalid_Descriptor,
		.Error,
		"Invalid layer count",
		"The layer count and the base layer must not be negative. Found base layer %d and layer count %d.",
		descriptor.base_layer,
		descriptor.layer_count,
		location=location,
	) or_return
	_check_condition(
		descriptor.base_mip >= 0 && descriptor.base_layer >= 0,
		.Invalid_Descriptor,
		.Error,
		"Invalid layer count",
		"The mip count and the base mip must not be negative. Found base mip %d and mip count %d.",
		descriptor.base_layer,
		descriptor.layer_count,
		location=location,
	) or_return
	
	_check_condition(
		descriptor.base_layer + descriptor.layer_count - 1 < texture_descriptor.layer_count,
		.Invalid_Descriptor,
		.Error,
		"Out of bounds layer access",
		"Out of bounds layer access: requested layers [%d-%d] for a texture with %d layers.",
		descriptor.base_layer,
		descriptor.base_layer + descriptor.layer_count,
		texture_descriptor.layer_count,
		location=location,
	) or_return
	_check_condition(
		descriptor.base_mip + descriptor.mip_count - 1 < texture_descriptor.mip_count,
		.Invalid_Descriptor,
		.Error,
		"Out of bounds mipmap access",
		"Out of bounds mipmap access: requested mipmap levels [%d-%d] for a texture with %d mipmap layers.",
		descriptor.base_mip,
		descriptor.base_mip + descriptor.mip_count - 1,
		texture_descriptor.mip_count,
		location=location,
	) or_return

	_check_condition(
		_impl(descriptor.type == .Cube || descriptor.type == .Cube_Array,
			_is_cube_compatible(texture_descriptor)),
		.Invalid_Descriptor,
		.Error,
		"Invalid view type",
		"Views or type `.Cube` and `.Cube_Array` are only compatible with cube-compatible textures (i.e. " +
		"`.D2` textures with the same x and y dimensions and with a layer count >= 6). Got a texture of type " +
		"%v, with dimensions %v and layer count %v.",
		texture_descriptor.type,
		texture_descriptor.dimensions,
		texture_descriptor.layer_count,
		location=location,
	) or_return
	
	return nil
}

_size_of_mipmap_level :: proc(metadata: ^_Texture_Metadata, mip_level: int) -> (size: [3]int) {
	size = metadata.dimensions

	switch metadata.type {
	case .D1:
		size.x <<= cast(uint)mip_level

	case .D2_Array:
		size.x <<= cast(uint)mip_level
		size.y <<= cast(uint)mip_level

	case .D3:
		size.x <<= cast(uint)mip_level
		size.y <<= cast(uint)mip_level
		size.z <<= cast(uint)mip_level
	}

	return
}

_size_of_texture_region :: proc(metadata: ^_Texture_Metadata, region: Texture_Region) -> int {
	pixel_size	:= SIZE_OF_PIXEL_FORMAT[metadata.format]

	return pixel_size * region.size.x * region.size.y * region.size.z * region.layer_count
}

_size_of_texture_region_layer :: proc(metadata: ^_Texture_Metadata, region: Texture_Region) -> int {
	pixel_size	:= SIZE_OF_PIXEL_FORMAT[metadata.format]

	return pixel_size * region.size.x * region.size.y * region.size.z
}

_size_of_texture_region_2d_image :: proc(metadata: ^_Texture_Metadata, region: Texture_Region) -> int {
	pixel_size	:= SIZE_OF_PIXEL_FORMAT[metadata.format]

	return pixel_size * region.size.x * region.size.y
}

_size_of_texture_region_row :: proc(metadata: ^_Texture_Metadata, region: Texture_Region) -> int {
	pixel_size	:= SIZE_OF_PIXEL_FORMAT[metadata.format]

	return pixel_size * region.size.x
}

_add_texture_metadata :: proc() -> (texture: Texture, metadata: ^_Texture_Metadata, res: Result) {
	sync.guard(&_textures_mutex)

	texture = hm.add(&_textures, _Texture_Metadata {}) or_return
	metadata = hm.get(&_textures, texture)

	return
}

_remove_texture_metadata :: proc(texture: Texture) {
	sync.guard(&_textures_mutex)

	hm.remove(&_textures, texture)
}

_check_view_handle :: proc(result: Result, view: View, location: runtime.Source_Code_Location) -> Result {
	_check_result(
		result,
		.Warning,
		"Invalid resource handle",
		"Invalid view handle (%v).",
		view,
		location=location,
	) or_return
	return nil
}

_view_metadata_of :: proc(view: View) -> (^_View_Metadata, Result) {
	sync.shared_guard(&_views_mutex)

	metadata, ok := hm.get(&_views, view)
	if !ok {
		return nil, .Invalid_View
	}
	
	return metadata, nil
}

_add_view_metadata :: proc() -> (view: View, metadata: ^_View_Metadata, res: Result) {
	sync.guard(&_views_mutex)

	view = hm.add(&_views, _View_Metadata {}) or_return
	metadata = hm.get(&_views, view)

	return
}

_remove_view_metadata :: proc(view: View) {
	sync.guard(&_views_mutex)

	hm.remove(&_views, view)
}

_texture_type_to_view_type :: proc(descriptor: Texture_Descriptor) -> View_Type {
	switch descriptor.type {
	case .D1:
		return .D1

	case .D2_Array:
		if descriptor.layer_count == 1 {
			return .D2
		} else {
			return .D2_Array
		}

	case .D3:
		return .D3
	}

	unreachable()
}

@(rodata)
SIZE_OF_PIXEL_FORMAT := [Pixel_Format]int {
	.None			= 0,
	.R8_Unorm		= 1,
	.RG8_Unorm		= 2,
	.RGBA8_Unorm		= 4,
	.RGBA8_Srgb		= 4,
	.BGRA8_Unorm		= 4,
	.BGRA8_Srgb		= 4,
	.R16_Float		= 2,
	.RG16_Float		= 4,
	.RGBA16_Float		= 8,
	.RGBA16_Unorm		= 8,
	.R16_Unorm		= 2,
	.RG16_Unorm		= 4,
	.R32_Float		= 4,
	.RG32_Float		= 8,
	.RGBA32_Float		= 16,
	.RG11B10_Float		= 4,
	.RGB10_A2_Unorm 	= 4,
	.RGB10_A2_Uint		= 4,
	.D32_Float		= 4,
	.D24_Unorm_S8_Uint	= 4,
	.D32_Float_S8_Uint	= 8, // TODO: Is this correct?
	.D16_Unorm		= 2,
}

@(rodata)
_COPY_TEXTURE_TO_TEXTURE_COMPATIBILITIES := [Pixel_Format][Pixel_Format]bool {
	.None			= {},
	.R8_Unorm		= #partial { .R8_Unorm = true },
	.RG8_Unorm		= #partial { .RG8_Unorm = true },
	.RGBA8_Unorm		= #partial { .RGBA8_Unorm = true, .RGBA8_Srgb = true },
	.RGBA8_Srgb		= #partial { .RGBA8_Unorm = true, .RGBA8_Srgb = true },
	.BGRA8_Unorm		= #partial { .BGRA8_Unorm = true, .BGRA8_Srgb = true },
	.BGRA8_Srgb		= #partial { .BGRA8_Unorm = true, .BGRA8_Srgb = true },
	.R16_Float		= #partial { .R16_Float = true },
	.RG16_Float		= #partial { .RG16_Float = true },
	.RGBA16_Float		= #partial { .RGBA16_Float = true },
	.RGBA16_Unorm		= #partial { .RGBA16_Unorm = true },
	.R16_Unorm		= #partial { .R16_Unorm = true },
	.RG16_Unorm		= #partial { .RG16_Unorm = true },
	.R32_Float		= #partial { .R32_Float = true },
	.RG32_Float		= #partial { .RG32_Float = true },
	.RGBA32_Float		= #partial { .RGBA32_Float = true },
	.RG11B10_Float		= #partial { .RG11B10_Float = true },
	.RGB10_A2_Unorm		= #partial { .RGB10_A2_Unorm = true },
	.RGB10_A2_Uint		= #partial { .RGB10_A2_Uint = true },
	.D32_Float		= #partial { .D32_Float = true },
	.D24_Unorm_S8_Uint	= #partial { .D24_Unorm_S8_Uint = true },
	.D32_Float_S8_Uint	= #partial { .D32_Float_S8_Uint = true },
	.D16_Unorm		= #partial { .D16_Unorm = true },
}

