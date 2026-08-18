package gfx

import vk "vendor:vulkan"

vk_Queue_Metadata :: struct {
	queue:		vk.Queue,
	queue_family:	u32,

	command_pool:	vk_Command_Pool,
}

vk_setup_queue :: proc(metadata: ^_Queue_Metadata) -> Result {
	queue_family:		u32
	queue_name:		cstring

	switch metadata.type {
	case .Default:
		queue_family		= vk_device_info.default_queue_family
		queue_name		= "Default queue"

	case .Transfer:
		queue_family		= vk_device_info.transfer_queue_family
		queue_name		= "Transfer queue"
	}

	queue: vk.Queue
	vk.GetDeviceQueue(vk_device, queue_family, 0, &queue)
	assert(queue != {})

	vk_label_object(queue, .QUEUE, queue_name)

	metadata.vk.command_pool = vk_create_command_pool(queue_family, _generic_allocator) or_return

	metadata.vk.queue = queue
	metadata.vk.queue_family = queue_family

	return nil
}

vk_destroy_queue :: proc(metadata: ^_Queue_Metadata) {
	vk.QueueWaitIdle(metadata.vk.queue)
	vk_destroy_command_pool(metadata.vk.command_pool)
}

