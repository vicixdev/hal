/*
This Source Code Form is subject to the terms of the Mozilla Public
License, v. 2.0. If a copy of the MPL was not distributed with this
file, You can obtain one at https://mozilla.org/MPL/2.0/.
*/

#+build darwin
package vicixdev_gfx

// import NS "core:sys/darwin/Foundation"
// import MTL "vendor:darwin/Metal"

// m3_Fence_Metadata :: struct {
// 	fence:	^MTL.Fence,
// }

// m3_create_fence :: proc(metadata: ^_Fence_Metadata) -> Result {
// 	NS.scoped_autoreleasepool()

// 	fence := m3_device->newFence()
// 	if fence == nil {
// 		return .Out_Of_Gpu_Memory
// 	}

// 	metadata.m3.fence = fence

// 	return nil
// }

// m3_destroy_fence :: proc(metadata: ^_Fence_Metadata) {
// 	NS.scoped_autoreleasepool()

// 	metadata.m3.fence->release()
// }


