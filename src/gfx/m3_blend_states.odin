#+build darwin
package vicixdev_gfx

// import NS "core:sys/darwin/Foundation"
import MTL "vendor:darwin/Metal"

m3_Blend_State_Metadata :: struct {}

m3_create_blend_state :: proc(
	metadata:	^_Blend_State_Metadata,
	descriptor:	Blend_Descriptor,
) -> Result {
	// NS.scoped_autoreleasepool()

	return nil
}

m3_destroy_blend_state :: proc(metadata: ^_Blend_State_Metadata) {
	// NS.scoped_autoreleasepool()
}

@(rodata)
m3_BLEND_OPERATION_TO_MTL := [Blend_Operation]MTL.BlendOperation {
	.Add			= .Add,
	.Subtract		= .Subtract,
	.Reverse_Subtract	= .ReverseSubtract,
	.Min			= .Min,
	.Max			= .Max,
}

@(rodata)
m3_BLEND_FACTOR_TO_MTL := [Blend_Factor]MTL.BlendFactor {
	.Zero				= .Zero,
	.One				= .One,
	.Source_Color			= .SourceColor,
	.Destination_Color		= .DestinationColor,
	.Source_Alpha			= .SourceAlpha,
	.Destination_Alpha		= .DestinationAlpha,
	.Constant_Color			= .BlendColor,
	.Constant_Alpha			= .BlendAlpha,
	.One_Minus_Source_Color		= .OneMinusSourceColor,
	.One_Minus_Destination_Color	= .OneMinusDestinationColor,
	.One_Minus_Source_Alpha		= .OneMinusSourceAlpha,
	.One_Minus_Destination_Alpha	= .OneMinusDestinationAlpha,
	.One_Minus_Constant_Color	= .OneMinusBlendColor,
	.One_Minus_Constant_Alpha	= .OneMinusBlendAlpha,
}

