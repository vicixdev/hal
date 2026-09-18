#+build darwin
package vicixdev_gfx

/*
This Source Code Form is subject to the terms of the Mozilla Public
License, v. 2.0. If a copy of the MPL was not distributed with this
file, You can obtain one at https://mozilla.org/MPL/2.0/.
*/

import NS "core:sys/darwin/Foundation"
import MTL "vendor:darwin/Metal"

_m3_Sampler_Metadata :: struct {
	sampler: ^MTL.SamplerState,
}

_m3_create_sampler :: proc(metadata: ^_Sampler_Metadata, descriptor: Sampler_Descriptor) -> Result {
	NS.scoped_autoreleasepool()

	sampler_desc := _m3_sampler_descriptor_to_mtl(descriptor)
	sampler := _m3_device->newSamplerState(sampler_desc)
	if sampler == nil {
		return .Generic_Backend_Error
	}
	
	metadata.m3.sampler = sampler

	return nil
}

_m3_destroy_sampler :: proc(metadata: ^_Sampler_Metadata) {
	NS.scoped_autoreleasepool()

	metadata.m3.sampler->release()
}

_m3_label_sampler :: proc(metadata: ^_Sampler_Metadata, label: string) -> Result {
	NS.scoped_autoreleasepool()

	// NOTE: Metal does not allow setting a sampler label after the creation.
	return nil
}

_m3_sampler_descriptor_to_mtl :: proc(descriptor: Sampler_Descriptor) -> (info: ^MTL.SamplerDescriptor) {
	info = MTL.SamplerDescriptor.alloc()->init()
	info->autorelease()

	info->setMagFilter(_m3_FILTER_TO_MTL[descriptor.mag_filter])
	info->setMinFilter(_m3_FILTER_TO_MTL[descriptor.min_filter])
	info->setMipFilter(_m3_FILTER_TO_MTL_MIPMAP[descriptor.mip_filter])

	info->setRAddressMode(_m3_ADDRESS_MODE_TO_MTL[descriptor.address_u])
	info->setSAddressMode(_m3_ADDRESS_MODE_TO_MTL[descriptor.address_v])
	info->setTAddressMode(_m3_ADDRESS_MODE_TO_MTL[descriptor.address_w])

	info->setBorderColor(_m3_BORDER_COLOR_TO_MTL[descriptor.border_color])

	if descriptor.max_anisotropy > 1 {
		info->setMaxAnisotropy(cast(NS.UInteger)descriptor.max_anisotropy)
	}

	info->setSupportArgumentBuffers(true)

	return
}

@(rodata)
_m3_FILTER_TO_MTL := [Filter]MTL.SamplerMinMagFilter {
	.Nearest	= .Nearest,
	.Linear		= .Linear,
}

@(rodata)
_m3_FILTER_TO_MTL_MIPMAP := [Filter]MTL.SamplerMipFilter {
	.Nearest	= .Nearest,
	.Linear		= .Linear,
}

@(rodata)
_m3_ADDRESS_MODE_TO_MTL := [Address_Mode]MTL.SamplerAddressMode {
	.Repeat			= .Repeat,
	.Mirrored_Repeat	= .MirrorRepeat,
	.Clamp_To_Edge		= .ClampToEdge,
	.Clamp_To_Border	= .ClampToBorderColor,
}

@(rodata)
_m3_BORDER_COLOR_TO_MTL := [Border_Color]MTL.SamplerBorderColor {
	.Transparent_Black_Float	= .TransparentBlack,
	.Transparent_Black_Int		= .TransparentBlack,
	.Opaque_Black_Float		= .OpaqueBlack,
	.Opaque_Black_Int		= .OpaqueBlack,
	.Opaque_White_Float		= .OpaqueWhite,
	.Opaque_White_Int		= .OpaqueWhite,
}


