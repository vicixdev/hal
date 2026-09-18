package vicixdev_gfx

/*
This Source Code Form is subject to the terms of the Mozilla Public
License, v. 2.0. If a copy of the MPL was not distributed with this
file, You can obtain one at https://mozilla.org/MPL/2.0/.
*/



import vk "vendor:vulkan"

_vk_Sampler_Metadata :: struct {
	sampler: vk.Sampler,
}

_vk_create_sampler :: proc(metadata: ^_Sampler_Metadata, descriptor: Sampler_Descriptor) -> Result {

	sampler_info := _vk_sampler_descriptor_to_vk(descriptor)
	
	sampler: vk.Sampler
	_vk_call(vk.CreateSampler(_vk_device, &sampler_info, nil, &sampler)) or_return

	metadata.vk.sampler = sampler

	return nil
}

_vk_destroy_sampler :: proc(metadata: ^_Sampler_Metadata) {
	vk.DestroySampler(_vk_device, metadata.vk.sampler, nil)
}

_vk_label_sampler :: proc(metadata: ^_Sampler_Metadata, label: string) -> Result {
	_vk_label_object(metadata.vk.sampler, .SAMPLER, label) or_return

	return nil
}

_vk_sampler_descriptor_to_vk :: proc(descriptor: Sampler_Descriptor) -> (info: vk.SamplerCreateInfo) {
	info.sType		= .SAMPLER_CREATE_INFO

	info.magFilter		= _vk_FILTER_TO_VK[descriptor.mag_filter]
	info.minFilter		= _vk_FILTER_TO_VK[descriptor.min_filter]
	info.mipmapMode		= _vk_FILTER_TO_VK_MIPMAP_MODE[descriptor.mip_filter]

	info.addressModeU	= _vk_ADDRESS_MODE_TO_VK[descriptor.address_u]
	info.addressModeV	= _vk_ADDRESS_MODE_TO_VK[descriptor.address_v]
	info.addressModeW	= _vk_ADDRESS_MODE_TO_VK[descriptor.address_w]

	info.borderColor	= _vk_BORDER_COLOR_TO_VK[descriptor.border_color]

	if descriptor.max_anisotropy > 1 {
		info.anisotropyEnable	= true
		info.maxAnisotropy	= cast(f32)descriptor.max_anisotropy
	}

	return
}

@(rodata)
_vk_FILTER_TO_VK := [Filter]vk.Filter {
	.Nearest	= .NEAREST,
	.Linear		= .LINEAR,
}

@(rodata)
_vk_FILTER_TO_VK_MIPMAP_MODE := [Filter]vk.SamplerMipmapMode {
	.Nearest	= .NEAREST,
	.Linear		= .LINEAR,
}

@(rodata)
_vk_ADDRESS_MODE_TO_VK := [Address_Mode]vk.SamplerAddressMode {
	.Repeat			= .REPEAT,
	.Mirrored_Repeat	= .MIRRORED_REPEAT,
	.Clamp_To_Edge		= .CLAMP_TO_EDGE,
	.Clamp_To_Border	= .CLAMP_TO_BORDER,
}

@(rodata)
_vk_BORDER_COLOR_TO_VK := [Border_Color]vk.BorderColor {
	.Transparent_Black_Float	= .FLOAT_TRANSPARENT_BLACK,
	.Transparent_Black_Int		= .INT_TRANSPARENT_BLACK,
	.Opaque_Black_Float		= .FLOAT_OPAQUE_BLACK,
	.Opaque_Black_Int		= .INT_OPAQUE_BLACK,
	.Opaque_White_Float		= .FLOAT_OPAQUE_WHITE,
	.Opaque_White_Int		= .INT_OPAQUE_WHITE,
}

