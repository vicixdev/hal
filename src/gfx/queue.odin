package gfx

import "core:sync"
import "core:mem"

Queue :: enum {
	Default,
	Transfer,
}

_Queue_Metadata :: struct {
	type:		Queue,

	scratch:	Scratch,
	emission_mutex:	sync.Mutex,

	using platform: struct #raw_union {
		vk:	vk_Queue_Metadata,
		m3:	m3_Queue_Metadata,
	},
}

_queues: [Queue]_Queue_Metadata

_init_queues :: proc() -> Result {
	_setup_queue(.Default) or_return
	if _device_info.properties.transfer_queue {
		_setup_queue(.Transfer) or_return
	}

	
	return nil
}

_fini_queues :: proc() {
	_destroy_queue(.Default)
	if _device_info.properties.transfer_queue {
		_destroy_queue(.Transfer)
	}
}

_setup_queue :: proc(queue: Queue) -> Result {
	_queues[queue].type = queue

	metadata, metadata_res := _queue_metadata_of(queue)
	assert(metadata_res == nil)

	create_scratch(&metadata.scratch, .Default, mem.Megabyte) or_return

	when TARGET_API == .Vulkan {
		vk_setup_queue(metadata) or_return
	} else {
		m3_setup_queue(metadata) or_return
	}
	_setup_command_buffers_of(queue)

	return nil
}

_destroy_queue :: proc(queue: Queue) {
	metadata, metadata_res := _queue_metadata_of(queue)
	assert(metadata_res == nil)

	_destroy_command_buffers_of(queue)
	when TARGET_API == .Vulkan {
		vk_destroy_queue(metadata)
	} else when TARGET_API == .Metal_3 {
		m3_destroy_queue(metadata)
	}
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

