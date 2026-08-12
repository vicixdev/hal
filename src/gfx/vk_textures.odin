package gfx

import "core:fmt"
import vk "vendor:vulkan"

vk_Texture_Metadata	:: struct {
	image:	vk.Image,
}

vk_View_Metadata	:: struct {
	view:	vk.ImageView,
}

vk_size_align_of :: proc(descriptor: Texture_Descriptor) -> (size: int, align: int, res: Result) {
	image_info := vk_texture_descriptor_to_vk(descriptor)
	
	image: vk.Image
	vk.CreateImage(vk_device, &image_info, nil, &image)
	defer vk.DestroyImage(vk_device, image, nil)

	requirements: vk.MemoryRequirements
	vk.GetImageMemoryRequirements(vk_device, image, &requirements)

	// TODO: check if maintenance4 is available
	// requirements_info := vk.DeviceImageMemoryRequirements {
	// 	sType		= .DEVICE_IMAGE_MEMORY_REQUIREMENTS,
	// 	pCreateInfo	= &image_info,
	// 	planeAspect	= {},
	// }
	// requirements := vk.MemoryRequirements2 {
	// 	sType		= .MEMORY_REQUIREMENTS_2,
	// }
	// vk.GetDeviceImageMemoryRequirements(vk_device, &requirements_info, &requirements)

	size	= cast(int)requirements.size
	align	= cast(int)requirements.alignment
	res	= nil
	return
}

vk_create_texture :: proc(
	metadata:		^_Texture_Metadata,
	buffer:			Buffer,
	buffer_metadata:	^_Buffer_Metadata,
	default_view_metadata:	^_View_Metadata,
	descriptor:		Texture_Descriptor,
) -> (res: Result) {

	image_info := vk_texture_descriptor_to_vk(descriptor)

	image: vk.Image
	vk_call(vk.CreateImage(vk_device, &image_info, nil, &image)) or_return
	defer if res != nil do vk.DestroyImage(vk_device, image, nil)

	vk_call(vk.BindImageMemory(
		vk_device,
		image,
		buffer_metadata.vk.device_memory,
		cast(vk.DeviceSize)_offset_from_base(buffer, buffer_metadata),
	)) or_return

	view_info := vk_texture_descriptor_to_vk_view(descriptor, image)

	view: vk.ImageView
	vk_call(vk.CreateImageView(vk_device, &view_info, nil, &view)) or_return
	defer if res != nil do vk.DestroyImage(vk_device, image, nil)

	metadata.vk.image		= image
	default_view_metadata.vk.view	= view

	return
}

vk_destroy_texture :: proc(metadata: ^_Texture_Metadata) {
	vk.DestroyImage(vk_device, metadata.vk.image, nil)
}

vk_label_texture :: proc(metadata: ^_Texture_Metadata, label: string) -> Result {
	vk_label_object(metadata.vk.image, .IMAGE, label) or_return

	view_metadata, view_res := _metadata_of(metadata.default_view)
	assert(view_res == nil, "Could not find the default view of an image.")

	vk_label_object(view_metadata.vk.view, .IMAGE_VIEW, fmt.ctprintf("%s (default view)", label)) or_return

	return nil
}

vk_create_view_with_descriptor :: proc(
	metadata:		^_View_Metadata,
	texture_metadata:	^_Texture_Metadata,
	descriptor:		View_Descriptor,
) -> Result {

	view_info := vk_view_descriptor_to_vk(descriptor, texture_metadata)

	view: vk.ImageView
	vk_call(vk.CreateImageView(vk_device, &view_info, nil, &view)) or_return

	metadata.vk.view = view

	return nil
}

vk_label_view :: proc(metadata: ^_View_Metadata, label: string) -> Result {
	vk_label_object(metadata.vk.view, .IMAGE_VIEW, label) or_return

	return nil
}

vk_destroy_view :: proc(metadata: ^_View_Metadata) {
	vk.DestroyImageView(vk_device, metadata.vk.view, nil)
}

vk_texture_descriptor_to_vk :: proc(descriptor: Texture_Descriptor) -> (info: vk.ImageCreateInfo) {
	info.sType		= .IMAGE_CREATE_INFO
	info.imageType		= vk_TEXTURE_TYPE_TO_VK[descriptor.type]

	info.format		= vk_PIXEL_FORMAT_TO_VK[descriptor.format]
	info.usage		= vk_texture_usages_to_vk(descriptor.usage)

	info.extent.width	= cast(u32)descriptor.dimensions.x
	info.extent.height	= cast(u32)descriptor.dimensions.y
	info.extent.depth	= cast(u32)descriptor.dimensions.z
	info.mipLevels		= cast(u32)descriptor.mip_count

	info.arrayLayers	= cast(u32)descriptor.layer_count

	info.tiling		= .OPTIMAL
	info.initialLayout	= .UNDEFINED
	info.sharingMode	= .EXCLUSIVE

	// TODO: Implement multisampling
	info.samples		= { ._1 }

	if descriptor.type == .Cube || descriptor.type == .Cube_Array || descriptor.type == .D2_Array {
		info.flags += { .CUBE_COMPATIBLE }
	}
	
	return
}

vk_texture_descriptor_to_vk_view :: proc(
	descriptor: Texture_Descriptor,
	image: vk.Image,
) -> (info: vk.ImageViewCreateInfo) {

	info.sType	= .IMAGE_VIEW_CREATE_INFO
	info.image	= image

	info.viewType	= vk_TEXTURE_TYPE_TO_VK_VIEW[descriptor.type]
	info.format	= vk_PIXEL_FORMAT_TO_VK[descriptor.format]

	info.subresourceRange.aspectMask	= vk_PIXEL_FORMAT_TO_VK_ASPECT_MASK[descriptor.format]
	info.subresourceRange.baseMipLevel	= 0
	info.subresourceRange.levelCount	= cast(u32)descriptor.mip_count
	info.subresourceRange.baseArrayLayer	= 0
	info.subresourceRange.layerCount	= cast(u32)descriptor.layer_count

	return
}

vk_view_descriptor_to_vk :: proc(
	descriptor:		View_Descriptor,
	texture_metadata:	^_Texture_Metadata,
) -> (info: vk.ImageViewCreateInfo) {
	
	info.sType	= .IMAGE_VIEW_CREATE_INFO
	info.image	= texture_metadata.vk.image

	info.viewType	= vk_TEXTURE_TYPE_TO_VK_VIEW[descriptor.type]
	info.format	= vk_PIXEL_FORMAT_TO_VK[texture_metadata.format]

	info.subresourceRange.aspectMask	= vk_PIXEL_FORMAT_TO_VK_ASPECT_MASK[texture_metadata.format]
	info.subresourceRange.baseMipLevel	= cast(u32)descriptor.base_mip
	info.subresourceRange.levelCount	= cast(u32)descriptor.mip_count
	info.subresourceRange.baseArrayLayer	= cast(u32)descriptor.base_layer
	info.subresourceRange.layerCount	= cast(u32)descriptor.layer_count

	return
}

vk_texture_usages_to_vk :: proc(usages: Texture_Usages) -> (flags: vk.ImageUsageFlags) {
	for usage in usages {
		flags += vk_TEXTURE_USAGE_TO_VK[usage]
	}

	return
}

@(rodata)
vk_TEXTURE_TYPE_TO_VK := [Texture_Type]vk.ImageType {
	.D1		= .D1,
	.D2		= .D2,
	.D3		= .D3,
	.Cube		= .D2,
	.D2_Array	= .D2,
	.Cube_Array	= .D2,
}

@(rodata)
vk_TEXTURE_TYPE_TO_VK_VIEW := [Texture_Type]vk.ImageViewType {
	.D1		= .D1,
	.D2		= .D2,
	.D3		= .D3,
	.Cube		= .CUBE,
	.D2_Array	= .D2_ARRAY,
	.Cube_Array	= .CUBE_ARRAY,
}

@(rodata)
vk_PIXEL_FORMAT_TO_VK := [Pixel_Format]vk.Format {
	.NONE			= .UNDEFINED,
	.R8_Unorm		= .R8_UNORM,
	.RG8_Unorm		= .R8G8_UNORM,
	.RGBA8_Unorm		= .R8G8B8A8_UNORM,
	.RGBA8_Srgb		= .R8G8B8A8_SRGB,
	.BGRA8_Unorm		= .B8G8R8A8_UNORM,
	.BGRA8_Srgb		= .B8G8R8A8_SRGB,
	.R16_Float		= .R16_SFLOAT,
	.RG16_Float		= .R16G16_SFLOAT,
	.RGBA16_Float		= .R16G16B16A16_SFLOAT,
	.RGBA16_Unorm		= .R16G16B16A16_UNORM,
	.R16_Unorm		= .R16_UNORM,
	.RG16_Unorm		= .R16G16_UNORM,
	.R32_Float		= .R32_SFLOAT,
	.RG32_Float		= .R32G32_SFLOAT,
	.RGBA32_Float		= .R32G32B32A32_SFLOAT,
	.RG11B10_Float		= .B10G11R11_UFLOAT_PACK32,
	.RGB10_A2_Unorm		= .A2R10G10B10_UNORM_PACK32,
	.RGB10_A2_Uint		= .A2R10G10B10_UINT_PACK32,
	.D32_Float		= .D32_SFLOAT,
	.D24_Unorm_S8_Uint	= .D24_UNORM_S8_UINT,
	.D32_Float_S8_Uint	= .D32_SFLOAT_S8_UINT,
	.D16_Unorm		= .D16_UNORM,
}

@(rodata)
vk_PIXEL_FORMAT_TO_VK_ASPECT_MASK := [Pixel_Format]vk.ImageAspectFlags {
	.NONE			= {},
	.R8_Unorm		= { .COLOR },
	.RG8_Unorm		= { .COLOR },
	.RGBA8_Unorm		= { .COLOR },
	.RGBA8_Srgb		= { .COLOR },
	.BGRA8_Unorm		= { .COLOR },
	.BGRA8_Srgb		= { .COLOR },
	.R16_Float		= { .COLOR },
	.RG16_Float		= { .COLOR },
	.RGBA16_Float		= { .COLOR },
	.RGBA16_Unorm		= { .COLOR },
	.R16_Unorm		= { .COLOR },
	.RG16_Unorm		= { .COLOR },
	.R32_Float		= { .COLOR },
	.RG32_Float		= { .COLOR },
	.RGBA32_Float		= { .COLOR },
	.RG11B10_Float		= { .COLOR },
	.RGB10_A2_Unorm		= { .COLOR },
	.RGB10_A2_Uint		= { .COLOR },
	.D32_Float		= { .DEPTH },
	.D24_Unorm_S8_Uint	= { .DEPTH, .STENCIL },
	.D32_Float_S8_Uint	= { .DEPTH, .STENCIL },
	.D16_Unorm		= { .DEPTH },
}

@(rodata)
vk_TEXTURE_USAGE_TO_VK := [Texture_Usage]vk.ImageUsageFlags {
	.Sampled			= { .SAMPLED, .TRANSFER_SRC, .TRANSFER_DST },
	.Storage			= { .STORAGE, .TRANSFER_SRC, .TRANSFER_DST },
	.Color_attachment		= { .COLOR_ATTACHMENT, .TRANSFER_SRC, .TRANSFER_DST },
	.Depth_stencil_attachment	= { .DEPTH_STENCIL_ATTACHMENT, .TRANSFER_SRC, .TRANSFER_DST },
}

