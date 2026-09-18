package vicixdev_gfx

/*
This Source Code Form is subject to the terms of the Mozilla Public
License, v. 2.0. If a copy of the MPL was not distributed with this
file, You can obtain one at https://mozilla.org/MPL/2.0/.
*/



import vk "vendor:vulkan"

_vk_Semaphore_Metadata :: struct {
	semaphore:	vk.Semaphore,
}

_vk_create_semaphore :: proc(metadata: ^_Semaphore_Metadata, type: Semaphore_Type) -> Result {
	semaphore_info: vk.SemaphoreCreateInfo
	switch metadata.type {
	case .Default:
		semaphore_type_info := vk.SemaphoreTypeCreateInfo {
			sType		= .SEMAPHORE_TYPE_CREATE_INFO,
			semaphoreType	= .BINARY,
			initialValue	= 0,
		}
		semaphore_info = vk.SemaphoreCreateInfo {
			sType	= .SEMAPHORE_CREATE_INFO,
			pNext	= &semaphore_type_info,
		}

	case .Timeline, .Cpu:
		semaphore_type_info := vk.SemaphoreTypeCreateInfo {
			sType		= .SEMAPHORE_TYPE_CREATE_INFO,
			semaphoreType	= .TIMELINE,
			initialValue	= 0,
		}
		semaphore_info = vk.SemaphoreCreateInfo {
			sType	= .SEMAPHORE_CREATE_INFO,
			pNext	= &semaphore_type_info,
		}

	case .Surface:
		unreachable()
	}

	semaphore: vk.Semaphore
	_vk_call(vk.CreateSemaphore(_vk_device, &semaphore_info, nil, &semaphore)) or_return

	metadata.vk.semaphore = semaphore

	return nil
}

_vk_destroy_semaphore :: proc(metadata: ^_Semaphore_Metadata) -> Result {
	if metadata.type != .Surface {
		vk.DestroySemaphore(_vk_device, metadata.vk.semaphore, nil)
	}

	return nil
}

_vk_wait_semaphore :: proc(metadata: ^_Semaphore_Metadata, value: int) -> Result {

	value := cast(u64)value
	wait_info := vk.SemaphoreWaitInfo {
		sType		= .SEMAPHORE_WAIT_INFO,
		semaphoreCount	= 1,
		pSemaphores	= &metadata.vk.semaphore,
		pValues		= &value,
	}
	_vk_call(vk.WaitSemaphores(_vk_device, &wait_info, max(u64))) or_return

	return nil
}
