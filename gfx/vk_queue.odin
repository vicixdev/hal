package vicixdev_gfx

/*
This Source Code Form is subject to the terms of the Mozilla Public
License, v. 2.0. If a copy of the MPL was not distributed with this
file, You can obtain one at https://mozilla.org/MPL/2.0/.
*/



import vk "vendor:vulkan"

_vk_Queue_Metadata :: struct {
	queue:		vk.Queue,
	queue_family:	u32,

	command_pool:	_vk_Command_Pool,
}

_vk_setup_queue :: proc(metadata: ^_Queue_Metadata) -> Result {
	queue_family:		u32
	queue_name:		cstring

	switch metadata.type {
	case .Default:
		queue_family		= _vk_device_info.default_queue_family
		queue_name		= "Default queue"

	case .Transfer:
		queue_family		= _vk_device_info.transfer_queue_family
		queue_name		= "Transfer queue"
	}

	queue: vk.Queue
	vk.GetDeviceQueue(_vk_device, queue_family, 0, &queue)
	assert(queue != {})

	_vk_label_object(queue, .QUEUE, queue_name)

	metadata.vk.command_pool = _vk_create_command_pool(queue_family, _generic_allocator) or_return

	metadata.vk.queue = queue
	metadata.vk.queue_family = queue_family

	return nil
}

_vk_destroy_queue :: proc(metadata: ^_Queue_Metadata) {
	_vk_destroy_command_pool(metadata.vk.command_pool)
}

_vk_wait_idle :: proc(metadata: ^_Queue_Metadata) -> Result {
	_vk_call(vk.QueueWaitIdle(metadata.vk.queue)) or_return
	
	return nil
}
