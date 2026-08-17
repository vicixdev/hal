package gfx

import vk "vendor:vulkan"

vk_Fence_Metadata :: struct {
	semaphore:		vk.Semaphore,
	last_signaled_value:	u64,
}

vk_create_fence :: proc(metadata: ^_Fence_Metadata) -> Result {
	
	semaphore_type_info := vk.SemaphoreTypeCreateInfo {
		sType		= .SEMAPHORE_TYPE_CREATE_INFO,
		semaphoreType	= .TIMELINE,
		initialValue	= 0,
	}
	semaphore_info := vk.SemaphoreCreateInfo {
		sType	= .SEMAPHORE_CREATE_INFO,
		pNext	= &semaphore_type_info,
	}
	semaphore: vk.Semaphore
	vk_call(vk.CreateSemaphore(vk_device, &semaphore_info, nil, &semaphore)) or_return

	metadata.vk.semaphore = semaphore

	return nil
}

vk_destroy_fence :: proc(metadata: ^_Fence_Metadata) {
	vk.DestroySemaphore(vk_device, metadata.vk.semaphore, nil)
}

