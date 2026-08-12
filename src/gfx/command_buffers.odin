package gfx

import "base:runtime"
import "core:mem"
import vmem "core:mem/virtual"

Command_Buffer	:: distinct Handle

_Command_Buffer_Metadata :: struct {
	handle:		Command_Buffer,

	arena:		vmem.Arena,
	allocator:	runtime.Allocator,

	queue:		Queue,
	in_use:		bool,

	resource_set:	Resource_Set,

	using platform:	struct #raw_union {
		vk:	vk_Command_Buffer_Metadata,
		m3:	m3_Command_Buffer_Metadata,
	},
}

_command_buffers: [Queue]_Command_Buffer_Metadata

_setup_command_buffer_of :: proc(queue: Queue) -> Result {
	queue_metadata := &_queues[queue]
	metadata := &_command_buffers[queue]

	metadata.handle.idx = cast(u32)queue
	metadata.queue = queue

	vmem.arena_init_growing(&metadata.arena) or_return
	metadata.allocator = vmem.arena_allocator(&metadata.arena)

	when TARGET_API == .Vulkan {
		vk_setup_command_buffer(metadata, queue_metadata) or_return
	} else when TARGET_API == .Metal_3 {
		m3_setup_command_buffer(metadata, queue_metadata) or_return
	}

	return nil
}

begin_command_encoding :: proc(
	queue: Queue,
	location := #caller_location,
) -> (command_buffer: Command_Buffer, res: Result) {

	_check_queue_validity(queue, location)
	queue_metadata, _ := _metadata_of(queue)
	
	handle, metadata, add_res := _add_command_buffer(queue)
	_check_result(
		add_res,
		.Error,
		"Queue already in use",
		"The queue `%v` is already in use by another command buffer. Please submit it before start encoding " +
		"another one.",
		queue,
		location=location,
	) or_return

	vmem.arena_free_all(&metadata.arena)

	metadata.resource_set	= _default_resource_set

	when TARGET_API == .Vulkan {
		res = vk_begin_command_encoding(metadata, queue_metadata)
	} else when TARGET_API == .Metal_3 {
		res = m3_begin_command_encoding(metadata, queue_metadata)
	}

	_check_generic_backend_error(res, location) or_return

	metadata.in_use = true

	setup_res := use_resources(handle, _default_resource_set)
	ensure(setup_res == nil, "Could not setup the default resource set. Broken implementation?")

	return handle, nil
}

use_resources :: proc(
	command_buffer:	Command_Buffer,
	resource_set:	Resource_Set,
	location :=	#caller_location,
) -> (res: Result) {
	
	metadata, metadata_res := _metadata_of(command_buffer)
	_check_command_buffer_handle(metadata_res, command_buffer, location) or_return

	resource_set_metadata, resource_set_res := _metadata_of(resource_set)
	_check_resource_set_handle(resource_set_res, resource_set, location) or_return
	
	metadata.resource_set = resource_set

	when TARGET_API == .Vulkan {
		res = vk_use_resources(metadata, resource_set_metadata)
	} else when TARGET_API == .Metal_3 {
		res = m3_use_resources(metadata, resource_set_metadata)
	}


	return nil
}

mem_copy :: proc(
	command_buffer:	Command_Buffer,
	destination:	Buffer,
	source:		Buffer,
	length:		int,
	location :=	#caller_location,
) -> (res: Result) {
	metadata, metadata_res := _metadata_of(command_buffer)
	_check_command_buffer_handle(metadata_res, command_buffer, location) or_return

	destination_metadata, destination_res := _metadata_of(destination)
	_check_result(
		destination_res,
		.Error,
		"Invalid resource handle",
		"The destination buffer handle is invalid (0x%x - %v).",
		destination.address,
		destination.handle,
	) or_return
	destination_offset := _offset_from_base(destination, destination_metadata)

	source_metadata, source_res := _metadata_of(source)
	_check_result(
		source_res,
		.Error,
		"Invalid resource handle",
		"The source buffer handle is invalid (0x%x - %v).",
		source.address,
		source.handle,
	) or_return
	source_offset := _offset_from_base(source, source_metadata)

	_check_condition(
		destination_metadata.size - cast(int)destination_offset >= length,
		.Out_Of_Bounds,
		.Error,
		"Out of bounds copy",
		"The requested memory copy operation would result in out of bounds accesses. The user specified a " +
		"copy lenth of %d, but the destination buffer (at 0x%x) has only %d bytes remaining at offset %d.",
		length,
		destination.address,
		destination_metadata.size - cast(int)destination_offset,
		destination_offset,
		location=location,
	) or_return
	_check_condition(
		source_metadata.size - cast(int)source_offset >= length,
		.Out_Of_Bounds,
		.Error,
		"Out of bounds copy",
		"The requested memory copy operation would result in out of bounds accesses. The user specified a " +
		"copy lenth of %d, but the source buffer (at 0x%x) has only %d bytes remaining at offset %d.",
		length,
		source.address,
		source_metadata.size - cast(int)source_offset,
		source_offset,
		location=location,
	) or_return

	_check_condition(
		source_metadata.memory_type != .Readback,
		.Incompatible_Memory_Type,
		.Error,
		"Incorrect source memory type",
		"The source buffer (at 0x%x) is of memory type `.Readback`. `.Readback` buffers can only be used as " +
		"destination. To upload data consider using `.Default` buffers for small memory sizes or `.Staging` " +
		"for bigger ones.",
		source.address,
		location=location,
	) or_return
	_check_condition(
		destination_metadata.memory_type != .Staging,
		.Incompatible_Memory_Type,
		.Error,
		"Incorrect destination memory type",
		"The destination buffer (at 0x%x) is of memory type `.Staging`. `.Staging` buffers can only be used " +
		"as source. To download data consider using `.Default` buffers for small memory sizes or `.Readback` " +
		"for bigger ones.",
		destination.address,
		location=location,
	) or_return

	when TARGET_API == .Vulkan {
		res = vk_mem_copy(
			metadata,
			destination_metadata,
			destination_offset,
			source_metadata,
			source_offset,
			length,
		)
	} else when TARGET_API == .Metal_3 {
		res = m3_mem_copy(
			metadata,
			destination_metadata,
			destination_offset,
			source_metadata,
			source_offset,
			length,
		)
	}

	_check_generic_backend_error(res, location) or_return

	return nil
}

dispatch_with_any_argument :: proc(
	command_buffer:		Command_Buffer,
	compute_pipeline:	Pipeline,
	argument:		any,
	group_count:		[3]int,
	location :=		#caller_location,
) -> Result {
	return dispatch_with_bytes_argument(command_buffer,
		compute_pipeline,
		mem.any_to_bytes(argument),
		group_count,
		location,
	)
}

dispatch_with_bytes_argument :: proc(
	command_buffer:		Command_Buffer,
	compute_pipeline:	Pipeline,
	argument:		[]byte,
	group_count:		[3]int,
	location :=		#caller_location,
) -> (res: Result) {
	
	_check_condition(
		len(argument) < 64,
		.Invalid_Pipeline_Argument,
		.Error,
		"Invalid pipeline argument",
		"The size of the pipeline argument must be at most 64 bytes (%d found).",
		len(argument),
		location=location,
	) or_return

	metadata, metadata_res := _metadata_of(command_buffer)
	_check_command_buffer_handle(metadata_res, command_buffer, location) or_return

	pipeline_metadata, pipeline_res := _metadata_of(compute_pipeline)
	_check_pipeline_handle(pipeline_res, compute_pipeline, location) or_return

	when TARGET_API == .Vulkan {
		res = vk_dispatch(metadata, pipeline_metadata, argument, group_count)
	} else when TARGET_API == .Metal_3 {
		res = m3_dispatch(metadata, pipeline_metadata, argument, group_count)
	}

	_check_generic_backend_error(res, location) or_return

	return nil
}

dispatch :: proc {
	dispatch_with_bytes_argument,
	dispatch_with_any_argument,
}

barrier	:: proc(command_buffer: Command_Buffer, after: Stages, before: Stages, location := #caller_location) {
	metadata, metadata_res := _metadata_of(command_buffer)
	_check_command_buffer_handle(metadata_res, command_buffer, location)
	if metadata_res != nil {
		return
	}

	res: Result
	when TARGET_API == .Vulkan {
		res = vk_barrier(metadata, after, before)
	} else {
		res = m3_barrier(metadata, after, before)
	}

	_check_generic_backend_error(res, location)
}

signal	:: proc(
	command_buffer: Command_Buffer,
	after: Stages,
	location := #caller_location,
) -> (fence: Fence, res: Result) {

	metadata, metadata_res := _metadata_of(command_buffer)
	_check_command_buffer_handle(metadata_res, command_buffer, location)
	if metadata_res != nil {
		return
	}

	fence, res = _create_managed_fence(location)
	_check_result(
		res,
		.Error,
		"Could not create fence",
		"Could not create a managed fence while encoding a signal operation on the command buffer %v.",
		command_buffer,
	) or_return

	fence_metadata, fence_metadata_res := _metadata_of(fence)
	ensure(fence_metadata_res == nil, "Could not obtain the metadata of a managed fence.")

	queue_metadata, queue_res := _queue_metadata_of(metadata.queue)
	ensure(queue_res == nil)

	when TARGET_API == .Vulkan {
		res = vk_signal_fence(metadata, queue_metadata, fence_metadata, after, 1)
	} else when TARGET_API == .Metal_3 {
		res = m3_signal_fence(metadata, queue_metadata, fence_metadata, after, 1)
	}

	_check_generic_backend_error(res, location) or_return

	fence_metadata.value += 1

	return fence, nil
}

wait :: proc(command_buffer: Command_Buffer, before: Stages, fence: Fence, location := #caller_location) {
	metadata, metadata_res := _metadata_of(command_buffer)
	_check_command_buffer_handle(metadata_res, command_buffer, location)
	if metadata_res != nil do return

	fence_metadata, fence_res := _metadata_of(fence)
	_check_fence_handle(fence_res, fence, location)
	if fence_res != nil do return

	queue_metadata, queue_res := _queue_metadata_of(metadata.queue)
	ensure(queue_res == nil)

	if fence_metadata.type != .Managed {
		_log_message(
			.Invalid_Arguments,
			.Error,
			"Invalid fence type",
			"The `gfx::wait` procedure only works with automatically managed fences. The provided fence %v is " +
			"manually managed.",
			fence,
		)
		return
	}

	res: Result
	when TARGET_API == .Vulkan {
		res = vk_wait_fence(metadata, queue_metadata, fence_metadata, before, 1)
	} else {
		res = m3_wait_fence(metadata, queue_metadata, fence_metadata, before, 1)
	}

	_check_generic_backend_error(res, location)

	destroy_fence(fence)
}

submit :: proc(command_buffer: Command_Buffer, location := #caller_location) {
	metadata, metadata_res := _metadata_of(command_buffer)
	_check_command_buffer_handle(metadata_res, command_buffer, location)
	if metadata_res != nil {
		return
	}

	queue_metadata, queue_res := _metadata_of(metadata.queue)
	assert(queue_res == nil)
	
	res: Result
	when TARGET_API == .Vulkan {
		res = vk_submit(metadata, queue_metadata)
	} else {
		res = m3_submit(metadata, queue_metadata)
	}

	_check_generic_backend_error(res, location)

	metadata.in_use = false
}
// value must be monotonically increasing.
submit_and_signal :: proc(
	command_buffer: Command_Buffer,
	semaphore: Semaphore,
	value: int,
	location := #caller_location,
) {

	metadata, metadata_res := _metadata_of(command_buffer)
	_check_command_buffer_handle(metadata_res, command_buffer, location)
	if metadata_res != nil do return
	
	queue_metadata, queue_res := _metadata_of(metadata.queue)
	assert(queue_res == nil)
	
	semaphore_metadata, semaphore_res := _metadata_of(semaphore)
	_check_semaphore_handle(semaphore_res, semaphore, location)
	if semaphore_res != nil do return

	if value <= semaphore_metadata.last_signaled_value {
		_log_message(
			.Invalid_Arguments,
			.Error,
			"Invalid signal value",
			"The values signaled to a semaphore must be monotonically (always) increasing. The last " +
			"signaled value on semaphore %v is %d, while a signaling of %d was requested.",
			semaphore,
			semaphore_metadata.last_signaled_value,
			value,
		)
		return
	}

	res: Result
	when TARGET_API == .Vulkan {
		res = vk_submit_and_signal(metadata, queue_metadata, semaphore_metadata, value)
	} else {
		res = m3_submit_and_signal(metadata, queue_metadata, semaphore_metadata, value)
	}
	
	_check_generic_backend_error(res, location)

	semaphore_metadata.last_signaled_value = value

	metadata.in_use = false
}

// wait_semaphore :: proc(semaphore: Semaphore, value: int) {}

_check_command_buffer_in_use :: proc(command_buffer: Command_Buffer, location: runtime.Source_Code_Location) -> Result {
	return nil
}

_check_command_buffer_handle :: proc(result: Result, command_buffer: Command_Buffer, location: runtime.Source_Code_Location) -> Result {
	_check_result(
		result,
		.Warning,
		"Invalid resource handle",
		"Invalid command buffer handle (%v).",
		command_buffer,
		location=location,
	) or_return
	return nil
}

_command_buffer_metadata_of :: proc(command_buffer: Command_Buffer) -> (^_Command_Buffer_Metadata, Result) {
	metadata: ^_Command_Buffer_Metadata
	if command_buffer.idx == 0 {
		metadata = &_command_buffers[.Default]
	} else {
		metadata = &_command_buffers[.Transfer]
	}

	if !metadata.in_use || metadata.handle.gen != command_buffer.gen {
		return nil, .Invalid_Command_Buffer
	}

	return metadata, nil
}

_add_command_buffer :: proc(queue: Queue) -> (handle: Command_Buffer, metadata: ^_Command_Buffer_Metadata, res: Result) {
	metadata = &_command_buffers[queue]

	if metadata.in_use {
		return {}, nil, .Queue_Already_In_Use
	}

	metadata.handle.gen += 1
	handle = metadata.handle

	return
}

_remove_command_buffer :: proc(command_buffer: Command_Buffer) {
	metadata, metadata_res := _command_buffer_metadata_of(command_buffer)
	if metadata_res != nil {
		return
	}

	metadata.in_use = false
}

