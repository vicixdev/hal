#+build darwin
package vicixdev_gfx

/*
This Source Code Form is subject to the terms of the Mozilla Public
License, v. 2.0. If a copy of the MPL was not distributed with this
file, You can obtain one at https://mozilla.org/MPL/2.0/.
*/

import NS "core:sys/darwin/Foundation"
import MTL "vendor:darwin/Metal"

_m3_Depth_Stencil_State_Metadata :: struct {
	depth_stencil_state:	^MTL.DepthStencilState,
}

_m3_create_depth_stencil_state :: proc(
	metadata:	^_Depth_Stencil_State_Metadata,
	descriptor:	Depth_Stencil_Descriptor,
) -> Result {
	NS.scoped_autoreleasepool()

	mtl_descriptor := _m3_depth_stencil_descriptor_to_mtl(descriptor)

	depth_stencil_state := _m3_device->newDepthStencilState(mtl_descriptor)
	if depth_stencil_state == nil {
		return .Generic_Backend_Error
	}

	metadata.m3.depth_stencil_state = depth_stencil_state

	return nil
}

_m3_destroy_depth_stencil_state :: proc(metadata: ^_Depth_Stencil_State_Metadata) {
	NS.scoped_autoreleasepool()

	metadata.m3.depth_stencil_state->release()
}

_m3_depth_stencil_descriptor_to_mtl :: proc(descriptor: Depth_Stencil_Descriptor) -> (mtl: ^MTL.DepthStencilDescriptor) {
	mtl = MTL.DepthStencilDescriptor.alloc()->init()
	mtl->autorelease()

	mtl->setDepthCompareFunction(_m3_COMPARE_OPERATION_TO_MTL[descriptor.depth_test])
	mtl->setDepthWriteEnabled(descriptor.depth_write)
	mtl->setFrontFaceStencil(_m3_stencil_descriptor_to_mtl(descriptor.stencil_front))
	mtl->setBackFaceStencil(_m3_stencil_descriptor_to_mtl(descriptor.stencil_back))

	return
}

_m3_stencil_descriptor_to_mtl :: proc(descriptor: Stencil_Descriptor) -> (mtl: ^MTL.StencilDescriptor) {
	mtl = MTL.StencilDescriptor.alloc()->init()
	mtl->autorelease()

	mtl->setStencilCompareFunction(_m3_COMPARE_OPERATION_TO_MTL[descriptor.test])
	mtl->setDepthStencilPassOperation(_m3_STENCIL_OPERATION_TO_MTL[descriptor.pass])
	mtl->setStencilFailureOperation(_m3_STENCIL_OPERATION_TO_MTL[descriptor.fail])
	mtl->setDepthFailureOperation(_m3_STENCIL_OPERATION_TO_MTL[descriptor.depth_fail])
	mtl->setReadMask(descriptor.read_mask)
	mtl->setWriteMask(descriptor.write_mask)

	return
}

@(rodata)
_m3_COMPARE_OPERATION_TO_MTL := [Compare_Operation]MTL.CompareFunction {
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
_m3_STENCIL_OPERATION_TO_MTL := [Stencil_Operation]MTL.StencilOperation {
	.Keep			= .Keep,
	.Zero			= .Zero,
	.Replace		= .Replace,
	.Increment_Clamp	= .IncrementClamp,
	.Decrement_Clamp	= .DecrementClamp,
	.Invert			= .Invert,
	.Increment_Wrap		= .IncrementWrap,
	.Decrement_Wrap		= .DecrementWrap,
}

