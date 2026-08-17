package gfx

import vk "vendor:vulkan"

vk_Semaphore_Metadata :: struct {
	semaphore:	vk.Semaphore,
}

vk_create_semaphore :: proc(metadata: ^_Semaphore_Metadata, type: Semaphore_Type) -> Result {
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

vk_destroy_semaphore :: proc(metadata: ^_Semaphore_Metadata) -> Result {
	vk.DestroySemaphore(vk_device, metadata.vk.semaphore, nil)

	return nil
}

vk_wait_semaphore :: proc(metadata: ^_Semaphore_Metadata, value: int) -> Result {

	value := cast(u64)value
	wait_info := vk.SemaphoreWaitInfo {
		sType		= .SEMAPHORE_WAIT_INFO,
		semaphoreCount	= 1,
		pSemaphores	= &metadata.vk.semaphore,
		pValues		= &value,
	}
	vk_call(vk.WaitSemaphores(vk_device, &wait_info, max(u64))) or_return

	return nil
}
