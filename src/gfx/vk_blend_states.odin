package gfx

import vk "vendor:vulkan"

vk_Blend_State_Metadata :: struct {}

vk_create_blend_state :: proc(
	metadata:	^_Blend_State_Metadata,
	descriptor:	Blend_Descriptor,
) -> Result {
	return nil
}

vk_destroy_blend_state :: proc(metadata: ^_Blend_State_Metadata) {}

@(rodata)
vk_BLEND_OP_TO_VK := [Blend_Operation]vk.BlendOp {
	.Add			= .ADD,
	.Subtract		= .SUBTRACT,
	.Reverse_Subtract	= .REVERSE_SUBTRACT,
	.Min			= .MIN,
	.Max			= .MAX,
}

@(rodata)
vk_BLEND_FACTOR_TO_VK := [Blend_Factor]vk.BlendFactor {
	.Zero				= .ZERO,
	.One				= .ONE,
	.Source_Color			= .SRC_COLOR,
	.Destination_Color		= .DST_COLOR,
	.Source_Alpha			= .SRC_ALPHA,
	.Destination_Alpha		= .DST_ALPHA,
	.Constant_Color			= .CONSTANT_COLOR,
	.Constant_Alpha			= .CONSTANT_ALPHA,
	.One_Minus_Source_Color		= .ONE_MINUS_SRC_COLOR,
	.One_Minus_Destination_Color	= .ONE_MINUS_DST_COLOR,
	.One_Minus_Source_Alpha		= .ONE_MINUS_SRC_ALPHA,
	.One_Minus_Destination_Alpha	= .ONE_MINUS_DST_ALPHA,
	.One_Minus_Constant_Color	= .ONE_MINUS_CONSTANT_COLOR,
	.One_Minus_Constant_Alpha	= .ONE_MINUS_CONSTANT_ALPHA,
}


