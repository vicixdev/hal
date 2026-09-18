package vicixdev_gfx

/*
This Source Code Form is subject to the terms of the Mozilla Public
License, v. 2.0. If a copy of the MPL was not distributed with this
file, You can obtain one at https://mozilla.org/MPL/2.0/.
*/



import vk "vendor:vulkan"

_vk_Depth_Stencil_State_Metadata :: struct {}

_vk_create_depth_stencil_state :: proc(
	metadata:	^_Depth_Stencil_State_Metadata,
	descriptor:	Depth_Stencil_Descriptor,
) -> Result {
	return nil
}

_vk_destroy_depth_stencil_state :: proc(metadata: ^_Depth_Stencil_State_Metadata) {}

@(rodata)
_vk_COMPARE_OPERATION_TO_VK := [Compare_Operation]vk.CompareOp {
	.Never		= .NEVER,
	.Less		= .LESS,
	.Equal		= .EQUAL,
	.Less_Equal	= .LESS_OR_EQUAL,
	.Greater	= .GREATER,
	.Not_Equal	= .NOT_EQUAL,
	.Greater_Equal	= .GREATER_OR_EQUAL,
	.Always		= .ALWAYS,
}

@(rodata)
_vk_STENCIL_OPERATION_TO_VK := [Stencil_Operation]vk.StencilOp {
	.Keep			= .KEEP,
	.Zero			= .ZERO,
	.Replace		= .REPLACE,
	.Increment_Clamp	= .INCREMENT_AND_CLAMP,
	.Decrement_Clamp	= .DECREMENT_AND_CLAMP,
	.Invert			= .INVERT,
	.Increment_Wrap		= .INCREMENT_AND_WRAP,
	.Decrement_Wrap		= .DECREMENT_AND_WRAP,
}


