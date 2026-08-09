package gfx

import vk "vendor:vulkan"

vk_Queue_Metadata :: struct {
	queue:		vk.Queue,
	command_pool:	vk.CommandPool,
}

vk_setup_queue :: proc(metadata: ^_Queue_Metadata) -> Result {
	queue_family:		u32
	queue_name:		cstring
	command_pool_name:	cstring

	switch metadata.type {
	case .Default:
		queue_family		= vk_device_info.default_queue_family
		queue_name		= "Default queue"
		command_pool_name	= "Default queue command pool"

	case .Transfer:
		queue_family		= vk_device_info.transfer_queue_family
		queue_name		= "Transfer queue"
		command_pool_name	= "Transfer queue command pool"
	}

	queue: vk.Queue
	vk.GetDeviceQueue(vk_device, queue_family, 0, &queue)
	assert(queue != {})

	vk_label_object(queue, .QUEUE, queue_name)

	command_pool: vk.CommandPool
	command_pool_desc := vk.CommandPoolCreateInfo {
		sType			= .COMMAND_POOL_CREATE_INFO,
		flags			= { .TRANSIENT, .RESET_COMMAND_BUFFER },
		queueFamilyIndex	= queue_family,
	}
	vk_call(vk.CreateCommandPool(vk_device, &command_pool_desc, nil, &command_pool)) or_return
	vk_label_object(command_pool, .COMMAND_POOL, command_pool_name)
	
	metadata.vk.queue = queue
	metadata.vk.command_pool = command_pool

	return nil
}

