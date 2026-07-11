#+build darwin
package gfx

import hm "core:container/handle_map"
import NS "core:sys/darwin/Foundation"
import MTL "vendor:darwin/Metal"

_Texture_Metadata :: struct {
	handle:		Texture,
	texture:	^MTL.Texture,
	self_view:	View,
}

_View_Metadata :: struct {
	handle:		View,
	view:		^MTL.Texture,
	parent_texture:	Texture,
	next_view:	View,
}

_textures:	hm.Dynamic_Handle_Map(_Texture_Metadata, Texture)
_views:		hm.Dynamic_Handle_Map(_View_Metadata, View)

_size_align_of :: proc(descriptor: Texture_Descriptor) -> (size: int, align: int, res: Result) {
	NS.scoped_autoreleasepool()

	mtl_desc := _texture_descriptor_to_mtl(descriptor)
	mtl_size, mtl_align := _device->heapTextureSizeAndAlignWithDescriptor(mtl_desc)

	return cast(int)mtl_size, cast(int)mtl_align, nil
}

_create_texture :: proc(buffer: Buffer, descriptor: Texture_Descriptor) -> (handle: Texture, res: Result) {
	NS.scoped_autoreleasepool()

	buffer_metadata, buffer_ok := hm.get(&_buffers, buffer.handle)
	if !buffer_ok {
		return {}, .Invalid_Buffer
	}

	mtl_desc := _texture_descriptor_to_mtl(descriptor)
	mtl_desc->setResourceOptions(_MEMORY_TO_RESOURCEOPTIONS[buffer_metadata.memory])

	offset := _offset_from_base(buffer, buffer_metadata)

	texture := buffer_metadata.heap->newTextureWithDescriptorAndOffset(mtl_desc, cast(NS.UInteger)offset)
	if (texture == nil) {
		return {}, .Out_Of_Gpu_Memory
	}

	metadata := _Texture_Metadata {
		texture = texture,
	}
	handle = hm.add(&_textures, metadata) or_return

	metadata_ptr, _ := hm.get(&_textures, handle)
	_setup_self_view(metadata_ptr) or_return

	return handle, nil
}

_destroy_texture :: proc(texture: Texture) {
	metadata, metadata_ok := hm.get(&_textures, texture)
	if !metadata_ok {
		return
	}

	view_begin := metadata.self_view
	view_it := metadata.self_view
	for {
		view, view_ok := hm.get(&_views, view_it)
		assert(view_ok, "Broken texture view chain.")
		assert(view.parent_texture == texture, "Broken texture view parent.")

		view.view->release()

		view_it = view.next_view
		hm.remove(&_views, view.handle)

		if view_it == view_begin {
			break
		}
	}

	metadata.texture->release()
	hm.remove(&_textures, texture)
}

_label_texture :: proc(texture: Texture, label: string) {
	metadata, ok := hm.get(&_textures, texture)
	if !ok {
		return
	}

	objc_label := NS.String.alloc()->initWithOdinString(label)
	defer objc_label->release()

	metadata.texture->setLabel(objc_label)
	
}

_texture_descriptor_to_mtl :: proc(descriptor: Texture_Descriptor) -> ^MTL.TextureDescriptor {
	mtl_desc := MTL.TextureDescriptor.alloc()->init()
	mtl_desc->autorelease()

	mtl_desc->setTextureType(_TEXTURE_TYPE_TO_MTL[descriptor.type])
	mtl_desc->setWidth(cast(NS.UInteger)descriptor.dimensions.x)
	mtl_desc->setHeight(cast(NS.UInteger)descriptor.dimensions.y)
	mtl_desc->setDepth(cast(NS.UInteger)descriptor.dimensions.z)
	mtl_desc->setMipmapLevelCount(cast(NS.UInteger)descriptor.mip_count)
	mtl_desc->setArrayLength(cast(NS.UInteger)descriptor.layer_count)
	mtl_desc->setSampleCount(cast(NS.UInteger)descriptor.sample_count)
	mtl_desc->setPixelFormat(_PIXEL_FORMAT_TO_MTL[descriptor.format])
	mtl_desc->setUsage(_TEXTURE_USAGE_TO_MTL[descriptor.usage])

	return mtl_desc
}

_setup_self_view :: proc(metadata: ^_Texture_Metadata) -> Result {
	metadata.texture->retain()
	view_metadata := _View_Metadata {
		view		= metadata.texture,
		parent_texture	= metadata.handle,
	}

	view := hm.add(&_views, view_metadata) or_return

	view_metadata_ptr, _ := hm.get(&_views, view)
	view_metadata_ptr.next_view = view

	metadata.self_view = view

	return nil
}

_create_default_view :: proc(texture: Texture) -> (View, Result) {
	metadata, ok := hm.get(&_textures, texture)
	if !ok {
		return {}, .Invalid_Texture
	}

	return metadata.self_view, nil
}

_create_view_with_descriptor :: proc(texture: Texture, descriptor: View_Descriptor) -> (handle: View, res: Result) {
	metadata, ok := hm.get(&_textures, texture)
	if !ok {
		return {}, .Invalid_Texture
	}

	self_view_metadata, self_view_ok := hm.get(&_views, metadata.self_view)
	assert(self_view_ok, "Invalid self view.")

	view := metadata.texture->newTextureViewWithLevelsAndSwizzle(
		_PIXEL_FORMAT_TO_MTL[descriptor.format],
		metadata.texture->textureType(),
		NS.Range_Make(cast(NS.UInteger)descriptor.base_mip, cast(NS.UInteger)descriptor.mip_count),
		NS.Range_Make(cast(NS.UInteger)descriptor.base_layer, cast(NS.UInteger)descriptor.layer_count),
		{
			red = _texture_swizzle_to_mtl(descriptor.swizzle.r, .R),
			green = _texture_swizzle_to_mtl(descriptor.swizzle.g, .G),
			blue = _texture_swizzle_to_mtl(descriptor.swizzle.b, .B),
			alpha = _texture_swizzle_to_mtl(descriptor.swizzle.a, .Alpha),
		},
	)

	view_metadata := _View_Metadata {
		view		= view,
		parent_texture	= texture,
		next_view	= self_view_metadata.next_view,
	}
	handle = hm.add(&_views, view_metadata) or_return

	self_view_metadata.next_view = handle

	return handle, nil
}

_label_view :: proc(view: View, label: string) {
	view, view_ok := hm.get(&_views, view)
	if !view_ok {
		return
	}

	objc_str := NS.String.alloc()->initWithOdinString(label)
	defer objc_str->release()

	view.view->setLabel(objc_str)
}

_texture_swizzle_to_mtl :: proc(swizzle: Texture_Channel_Swizzle, identity: Texture_Channel_Swizzle) -> MTL.TextureSwizzle {
	@(static, rodata)
	TEXTURE_CHANNEL_SWIZZLE_TO_MTL := [Texture_Channel_Swizzle]MTL.TextureSwizzle {
		.Identity = .Zero,
		.Zero = .Zero,
		.One = .One,
		.R = .Red,
		.G = .Green,
		.B = .Blue,
		.Alpha = .Alpha,
	}

	assert(identity != .Identity)

	if swizzle == identity {
		return TEXTURE_CHANNEL_SWIZZLE_TO_MTL[identity]
	} else {
		return TEXTURE_CHANNEL_SWIZZLE_TO_MTL[swizzle]
	}
}

@(rodata)
_TEXTURE_TYPE_TO_MTL := [Texture_Type]MTL.TextureType {
	.D1		= .Type1D,
	.D2		= .Type2D,
	.D3		= .Type3D,
	.CUBE		= .TypeCube,
	.D2_ARRAY	= .Type2DArray,
	.CUBE_ARRAY	= .TypeCubeArray,
}

@(rodata)
_PIXEL_FORMAT_TO_MTL := [Pixel_Format]MTL.PixelFormat {
	.NONE			= .Invalid,
	.R8_Unorm		= .R8Unorm,
	.RG8_Unorm		= .RG8Unorm,
	.RGBA8_Unorm		= .RGBA8Unorm,
	.RGBA8_Srgb		= .RGBA8Unorm_sRGB,
	.BGRA8_Unorm		= .BGRA8Unorm,
	.BGRA8_Srgb		= .BGRA8Unorm_sRGB,
	.R16_Float		= .R16Float,
	.RG16_Float		= .RG16Float,
	.RGBA16_Float		= .RGBA16Float,
	.RGBA16_Unorm		= .RGBA16Unorm,
	.R16_Unorm		= .R16Unorm,
	.RG16_Unorm		= .RG16Unorm,
	.R32_Float		= .R32Float,
	.RG32_Float		= .RG32Float,
	.RGBA32_Float		= .RGBA32Float,
	.RG11B10_Float		= .RG11B10Float,
	.RGB10_A2_Unorm		= .RGB10A2Unorm,
	.RGB10_A2_Uint		= .RGB10A2Uint,
	.D32_Float		= .Depth32Float,
	.D24_Unorm_S8_Uint	= .Depth24Unorm_Stencil8,
	.D32_Float_S8_Uint	= .Depth32Float_Stencil8,
	.D16_Unorm		= .Depth16Unorm,
}

@(rodata)
_TEXTURE_USAGE_TO_MTL := [Texture_Usage]MTL.TextureUsage {
	.Sampled			= { .PixelFormatView, .ShaderRead },
	.Storage			= { .PixelFormatView, .ShaderRead, .ShaderWrite },
	.Color_attachment		= { .PixelFormatView, .RenderTarget, .ShaderRead, .ShaderWrite },
	.Depth_stencil_attachment	= { .PixelFormatView, .RenderTarget, .ShaderRead, .ShaderWrite },
}

