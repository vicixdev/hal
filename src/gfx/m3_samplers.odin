#+build darwin
package gfx

import NS "core:sys/darwin/Foundation"
import MTL "vendor:darwin/Metal"

m3_Sampler_Metadata :: struct {
	sampler: ^MTL.SamplerState,
}

m3_create_sampler :: proc(metadata: ^_Sampler_Metadata, descriptor: Sampler_Descriptor) -> Result {

	sampler_desc := m3_sampler_descriptor_to_mtl(descriptor)
	sampler := m3_device->newSamplerState(sampler_desc)
	if sampler == nil {
		return .Generic_Backend_Error
	}
	
	metadata.m3.sampler = sampler

	return nil
}

m3_destroy_sampler :: proc(metadata: ^_Sampler_Metadata) {
	metadata.m3.sampler->release()
}

m3_label_sampler :: proc(metadata: ^_Sampler_Metadata, label: string) -> Result {
	// NOTE: Metal does not allow setting a sampler label after the creation.
	return nil
}

m3_sampler_descriptor_to_mtl :: proc(descriptor: Sampler_Descriptor) -> (info: ^MTL.SamplerDescriptor) {
	info = MTL.SamplerDescriptor.alloc()->init()
	info->autorelease()

	info->setMagFilter(m3_FILTER_TO_MTL[descriptor.mag_filter])
	info->setMagFilter(m3_FILTER_TO_MTL[descriptor.min_filter])
	info->setMipFilter(m3_FILTER_TO_MTL_MIPMAP[descriptor.mip_filter])

	info->setRAddressMode(m3_ADDRESS_MODE_TO_MTL[descriptor.address_u])
	info->setSAddressMode(m3_ADDRESS_MODE_TO_MTL[descriptor.address_v])
	info->setTAddressMode(m3_ADDRESS_MODE_TO_MTL[descriptor.address_w])

	info->setBorderColor(m3_BORDER_COLOR_TO_MTL[descriptor.border_color])

	if descriptor.max_anisotropy > 1 {
		info->setMaxAnisotropy(cast(NS.UInteger)descriptor.max_anisotropy)
	}

	return
}

@(rodata)
m3_FILTER_TO_MTL := [Filter]MTL.SamplerMinMagFilter {
	.Nearest	= .Nearest,
	.Linear		= .Linear,
}

@(rodata)
m3_FILTER_TO_MTL_MIPMAP := [Filter]MTL.SamplerMipFilter {
	.Nearest	= .Nearest,
	.Linear		= .Linear,
}

@(rodata)
m3_ADDRESS_MODE_TO_MTL := [Address_Mode]MTL.SamplerAddressMode {
	.Repeat			= .Repeat,
	.Mirrored_Repeat	= .MirrorRepeat,
	.Clamp_To_Edge		= .ClampToEdge,
	.Clamp_To_Border	= .ClampToBorderColor,
}

@(rodata)
m3_BORDER_COLOR_TO_MTL := [Border_Color]MTL.SamplerBorderColor {
	.Transparent_Black_Float	= .TransparentBlack,
	.Transparent_Black_Int		= .TransparentBlack,
	.Opaque_Black_Float		= .OpaqueBlack,
	.Opaque_Black_Int		= .OpaqueBlack,
	.Opaque_White_Float		= .OpaqueWhite,
	.Opaque_White_Int		= .OpaqueWhite,
}


