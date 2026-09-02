package vicixdev_gfx

import vk "vendor:vulkan"

vk_Depth_Stencil_State_Metadata :: struct {}

vk_create_depth_stencil_state :: proc(
	metadata:	^_Depth_Stencil_State_Metadata,
	descriptor:	Depth_Stencil_Descriptor,
) -> Result {
	return nil
}

vk_destroy_depth_stencil_state :: proc(metadata: ^_Depth_Stencil_State_Metadata) {}

@(rodata)
vk_COMPARE_OPERATION_TO_VK := [Compare_Operation]vk.CompareOp {
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
vk_STENCIL_OPERATION_TO_VK := [Stencil_Operation]vk.StencilOp {
	.Keep			= .KEEP,
	.Zero			= .ZERO,
	.Replace		= .REPLACE,
	.Increment_Clamp	= .INCREMENT_AND_CLAMP,
	.Decrement_Clamp	= .DECREMENT_AND_CLAMP,
	.Invert			= .INVERT,
	.Increment_Wrap		= .INCREMENT_AND_WRAP,
	.Decrement_Wrap		= .DECREMENT_AND_WRAP,
}


