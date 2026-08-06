package gfx

Queue :: enum {
	Default,
	Transfer,
}

_Queue_Metadata :: struct {
	type:	Queue,

	has_open_command_buffer:	bool,

	using platform: struct #raw_union {
		vk:	struct {},
		m3:	m3_Queue_Metadata,
	},
}

_queues: [Queue]_Queue_Metadata

_setup_queues :: proc() -> Result {
	_queues[.Default].type	= .Default
	_queues[.Transfer].type	= .Transfer

	when TARGET_API == .Vulkan {
		vk_setup_queue(_queue_metadata_of(.Default)) or_return
	} else {
		m3_setup_queue(_queue_metadata_of(.Default)) or_return
	}

	if _device_info.properties.transfer_queue {
		when TARGET_API == .Vulkan {
			vk_setup_queue(_queue_metadata_of(.Transfer)) or_return
		} else {
			m3_setup_queue(_queue_metadata_of(.Transfer)) or_return
		}
	}

	return nil
}

_queue_metadata_of :: proc(queue: Queue) -> ^_Queue_Metadata {
	return &_queues[queue]
}

