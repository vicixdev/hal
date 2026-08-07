package gfx

Queue :: enum {
	Default,
	Transfer,
}

_Queue_Metadata :: struct {
	type:	Queue,

	using platform: struct #raw_union {
		vk:	vk_Queue_Metadata,
		m3:	m3_Queue_Metadata,
	},
}

_queues: [Queue]_Queue_Metadata

_setup_queues :: proc() -> Result {
	_queues[.Default].type	= .Default
	_queues[.Transfer].type	= .Transfer

	default_queue, _ := _queue_metadata_of(.Default)
	when TARGET_API == .Vulkan {
		vk_setup_queue(default_queue) or_return
	} else {
		m3_setup_queue(default_queue) or_return
	}
	_setup_command_buffer_of(.Default)

	if _device_info.properties.transfer_queue {
		transfer_queue := _queue_metadata_of(.Transfer) or_return

		when TARGET_API == .Vulkan {
			vk_setup_queue(transfer_queue) or_return
		} else {
			m3_setup_queue(transfer_queue) or_return
		}

		_setup_command_buffer_of(.Transfer)
	}

	return nil
}

_queue_metadata_of :: proc(queue: Queue) -> (^_Queue_Metadata, Result) {
	if !_impl(queue == .Transfer, _device_info.properties.transfer_queue) {
		return nil, .Invalid_Queue
	}

	return &_queues[queue], nil
}

_check_queue_validity :: proc(queue: Queue, location := #caller_location) -> Result {
	_check_condition(
		_impl(queue == .Transfer, _device_info.properties.transfer_queue),
		.Invalid_Queue,
		.Error,
		"Invalid queue",
		"The user requested the `.Transfer` queue, but the current system does not support it (as shown in " +
		"device_info.properties.transfer_queue).",
		location=location,
	) or_return
	return nil
}

