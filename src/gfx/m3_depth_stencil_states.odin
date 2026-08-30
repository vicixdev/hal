#+build darwin
package gfx

import NS "core:sys/darwin/Foundation"
import MTL "vendor:darwin/Metal"

m3_Depth_Stencil_State_Metadata :: struct {
	depth_stencil_state:	^MTL.DepthStencilState,
}

m3_create_depth_stencil_state :: proc(
	metadata:	^_Depth_Stencil_State_Metadata,
	descriptor:	Depth_Stencil_Descriptor,
) -> Result {
	NS.scoped_autoreleasepool()

	mtl_descriptor := m3_depth_stencil_descriptor_to_mtl(descriptor)

	depth_stencil_state := m3_device->newDepthStencilState(mtl_descriptor)
	if depth_stencil_state == nil {
		return .Generic_Backend_Error
	}

	metadata.m3.depth_stencil_state = depth_stencil_state

	return nil
}

m3_destroy_depth_stencil_state :: proc(metadata: ^_Depth_Stencil_State_Metadata) {
	NS.scoped_autoreleasepool()

	metadata.m3.depth_stencil_state->release()
}

m3_depth_stencil_descriptor_to_mtl :: proc(descriptor: Depth_Stencil_Descriptor) -> (mtl: ^MTL.DepthStencilDescriptor) {
	mtl = MTL.DepthStencilDescriptor.alloc()->init()
	mtl->autorelease()

	mtl->setDepthCompareFunction(m3_COMPARE_OPERATION_TO_MTL[descriptor.depth_test])
	mtl->setDepthWriteEnabled(descriptor.depth_write)
	mtl->setFrontFaceStencil(m3_stencil_descriptor_to_mtl(descriptor.stencil_front))
	mtl->setBackFaceStencil(m3_stencil_descriptor_to_mtl(descriptor.stencil_back))

	return
}

m3_stencil_descriptor_to_mtl :: proc(descriptor: Stencil_Descriptor) -> (mtl: ^MTL.StencilDescriptor) {
	mtl = MTL.StencilDescriptor.alloc()->init()
	mtl->autorelease()

	mtl->setStencilCompareFunction(m3_COMPARE_OPERATION_TO_MTL[descriptor.test])
	mtl->setDepthStencilPassOperation(m3_STENCIL_OPERATION_TO_MTL[descriptor.pass])
	mtl->setStencilFailureOperation(m3_STENCIL_OPERATION_TO_MTL[descriptor.fail])
	mtl->setDepthFailureOperation(m3_STENCIL_OPERATION_TO_MTL[descriptor.depth_fail])
	mtl->setReadMask(descriptor.read_mask)
	mtl->setWriteMask(descriptor.write_mask)

	return
}

@(rodata)
m3_COMPARE_OPERATION_TO_MTL := [Compare_Operation]MTL.CompareFunction {
	.Never		= .Never,
	.Less		= .Less,
	.Equal		= .Equal,
	.Less_Equal	= .LessEqual,
	.Greater	= .Greater,
	.Not_Equal	= .NotEqual,
	.Greater_Equal	= .GreaterEqual,
	.Always		= .Always,
}

@(rodata)
m3_STENCIL_OPERATION_TO_MTL := [Stencil_Operation]MTL.StencilOperation {
	.Keep			= .Keep,
	.Zero			= .Zero,
	.Replace		= .Replace,
	.Increment_Clamp	= .IncrementClamp,
	.Decrement_Clamp	= .DecrementClamp,
	.Invert			= .Invert,
	.Increment_Wrap		= .IncrementWrap,
	.Decrement_Wrap		= .DecrementWrap,
}

