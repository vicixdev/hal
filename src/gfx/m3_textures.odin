#+build darwin
package gfx

import NS "core:sys/darwin/Foundation"
import MTL "vendor:darwin/Metal"

m3_Texture_Metadata :: struct {
	texture:	^MTL.Texture,
}

m3_View_Metadata :: struct {
	view:		^MTL.Texture,
	drawable:	^MTL.Drawable,
}

m3_size_align_of :: proc(descriptor: Texture_Descriptor) -> (size: int, align: int, res: Result) {
	NS.scoped_autoreleasepool()

	mtl_desc := m3_texture_descriptor_to_mtl(descriptor)
	mtl_size, mtl_align := m3_device->heapTextureSizeAndAlignWithDescriptor(mtl_desc)

	return cast(int)mtl_size, cast(int)mtl_align, nil
}

m3_create_texture :: proc(
	metadata:		^_Texture_Metadata,
	buffer:			Buffer,
	buffer_metadata:	^_Buffer_Metadata,
	default_view_metadata:	^_View_Metadata,
	descriptor: Texture_Descriptor,
) -> Result {
	NS.scoped_autoreleasepool()

	mtl_desc := m3_texture_descriptor_to_mtl(descriptor)
	mtl_desc->setResourceOptions(m3_MEMORY_TO_RESOURCEOPTIONS[buffer_metadata.memory_type])

	offset := _offset_from_base(buffer, buffer_metadata)

	texture := buffer_metadata.m3.heap->newTextureWithDescriptorAndOffset(mtl_desc, cast(NS.UInteger)offset)
	if (texture == nil) {
		return .Out_Of_Gpu_Memory
	}

	metadata.m3.texture = texture

	texture->retain()
	default_view_metadata.m3.view = texture

	return nil
}

m3_destroy_texture :: proc(metadata: ^_Texture_Metadata) {
	NS.scoped_autoreleasepool()
	
	metadata.m3.texture->release()
}

m3_label_texture :: proc(metadata: ^_Texture_Metadata, label: string) -> Result {
	NS.scoped_autoreleasepool()
	
	// FIXME: This works as long as the label is statically allocated, since `initWithOdinString` does not copy the
	//	string, only references it.

	texture_label := NS.String.alloc()->initWithOdinString(label)
	defer texture_label->release()

	metadata.m3.texture->setLabel(texture_label)

	return nil
}

m3_texture_descriptor_to_mtl :: proc(descriptor: Texture_Descriptor) -> ^MTL.TextureDescriptor {
	mtl_desc := MTL.TextureDescriptor.alloc()->init()
	mtl_desc->autorelease()

	mtl_desc->setTextureType(m3_texture_type_to_mtl(descriptor))
	mtl_desc->setWidth(cast(NS.UInteger)descriptor.dimensions.x)
	mtl_desc->setHeight(cast(NS.UInteger)descriptor.dimensions.y)
	mtl_desc->setDepth(cast(NS.UInteger)descriptor.dimensions.z)
	mtl_desc->setMipmapLevelCount(cast(NS.UInteger)descriptor.mip_count)
	mtl_desc->setSampleCount(cast(NS.UInteger)descriptor.sample_count)
	mtl_desc->setPixelFormat(m3_PIXEL_FORMAT_TO_MTL[descriptor.format])
	mtl_desc->setUsage(m3_texture_usages_to_mtl(descriptor.usage))
	mtl_desc->setArrayLength(cast(NS.UInteger)descriptor.layer_count)

	return mtl_desc
}

m3_create_view_with_descriptor :: proc(
	metadata:		^_View_Metadata,
	texture_metadata:	^_Texture_Metadata,
	descriptor:		View_Descriptor,
) -> Result {
	NS.scoped_autoreleasepool()

	view := texture_metadata.m3.texture->newTextureViewWithLevels(
		m3_PIXEL_FORMAT_TO_MTL[texture_metadata.format],
		m3_VIEW_TYPE_TO_MTL[descriptor.type],
		NS.Range_Make(cast(NS.UInteger)descriptor.base_mip, cast(NS.UInteger)descriptor.mip_count),
		NS.Range_Make(cast(NS.UInteger)descriptor.base_layer, cast(NS.UInteger)descriptor.layer_count),
	)
	if view == nil {
		return .Out_Of_Gpu_Memory
	}

	metadata.m3.view = view

	return nil
}

m3_destroy_view :: proc(metadata: ^_View_Metadata) {
	NS.scoped_autoreleasepool()

	metadata.m3.view->release()
}

m3_label_view :: proc(metadata: ^_View_Metadata, label: string) -> Result {
	NS.scoped_autoreleasepool()

	objc_str := NS.String.alloc()->initWithOdinString(label)
	defer objc_str->release()

	metadata.m3.view->setLabel(objc_str)

	return nil
}

m3_texture_usages_to_mtl :: proc(usages: Texture_Usages) -> (mtl: MTL.TextureUsage) {
	for usage in usages {
		mtl += m3_TEXTURE_USAGE_TO_MTL[usage]
	}

	return
}

m3_texture_type_to_mtl :: proc(descriptor: Texture_Descriptor) -> MTL.TextureType {
	switch descriptor.type {
	case .D1:
		return .Type1D

	case .D2_Array:
		if descriptor.layer_count == 1 {
			return .Type2D
		} else {
			return .Type2DArray
		}

	case .D3:
		return .Type3D
	}

	return nil
}

@(rodata)
m3_VIEW_TYPE_TO_MTL := [View_Type]MTL.TextureType {
	.D1		= .Type1D,
	.D2		= .Type2D,
	.D3		= .Type3D,
	.Cube		= .TypeCube,
	.D2_Array	= .Type2DArray,
	.Cube_Array	= .TypeCubeArray,
}

@(rodata)
m3_PIXEL_FORMAT_TO_MTL := [Pixel_Format]MTL.PixelFormat {
	.None			= .Invalid,
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
m3_TEXTURE_USAGE_TO_MTL := [Texture_Usage]MTL.TextureUsage {
	.Sampled			= { .PixelFormatView, .ShaderRead },
	.Storage			= { .PixelFormatView, .ShaderRead, .ShaderWrite },
	.Color_Attachment		= { .PixelFormatView, .RenderTarget, },
	.Depth_Stencil_Attachment	= { .PixelFormatView, .RenderTarget, },
}

