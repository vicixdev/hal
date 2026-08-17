package gfx

import "base:runtime"
import "core:mem"
import "core:slice"
import vmem "core:mem/virtual"

Command_Buffer	:: distinct Handle

Semaphore_Wait :: struct {
	semaphore:	Semaphore,
	value:		int,
}

Semaphore_Signal :: struct {
	semaphore:	Semaphore,
	value:		int,
}

_Command_Buffer_Metadata :: struct {
	handle:		Command_Buffer,

	arena:		vmem.Arena,
	allocator:	runtime.Allocator,

	queue:		Queue,
	in_use:		bool,

	resource_set:	Resource_Set,
	commands:	[dynamic]_Command,

	using platform:	struct #raw_union {
		vk:	vk_Command_Buffer_Metadata,
		m3:	m3_Command_Buffer_Metadata,
	},
}

_Command :: union {
	_Command_Mem_Copy,
	_Command_Dispatch,
	_Command_Barrier,
	_Command_Signal,
	_Command_Wait,
}

_Command_Mem_Copy :: struct {
	source:		Buffer,
	destination:	Buffer,
	size:		int,
}

_Command_Barrier :: struct {
	after:		Stages,
	before:		Stages,
}

_Command_Dispatch :: struct {
	pipeline:	Pipeline,
	resource_set:	Resource_Set,
	argument:	[]byte,
	group_count:	[3]int,
}

_Command_Signal :: struct {
	signals:	[]Fence,
}

_Command_Wait :: struct {
	waits:		[]Fence,
}

_Command_Signal_Semaphore :: struct {
	semaphore:	Semaphore,
	value:		int,
}

_command_buffers: [Queue]_Command_Buffer_Metadata

_setup_command_buffer_of :: proc(queue: Queue) -> Result {
	queue_metadata := &_queues[queue]
	metadata := &_command_buffers[queue]

	metadata.handle.idx = cast(u32)queue
	metadata.queue = queue

	vmem.arena_init_growing(&metadata.arena) or_return
	metadata.allocator = vmem.arena_allocator(&metadata.arena)

	metadata.commands	= make([dynamic]_Command, metadata.allocator) or_return

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
	metadata.in_use = true

	return handle, nil
}

wait_semaphores :: proc(
	command_buffer: Command_Buffer,
	waits: ..Semaphore_Wait,
	location := #caller_location,
) -> Result {

	// TODO:
	//	- check that the cb does not have any other command encoded

	return nil
}

use_resources :: proc(
	command_buffer:	Command_Buffer,
	resource_set:	Resource_Set,
	location :=	#caller_location,
) -> (res: Result) {
	
	metadata, metadata_res := _metadata_of(command_buffer)
	_check_command_buffer_handle(metadata_res, command_buffer, location) or_return

	_, resource_set_res := _metadata_of(resource_set)
	_check_resource_set_handle(resource_set_res, resource_set, location) or_return
	
	metadata.resource_set = resource_set

	return nil
}

mem_copy :: proc(
	command_buffer:	Command_Buffer,
	destination:	Buffer,
	source:		Buffer,
	size:		int,
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
		destination_metadata.size - cast(int)destination_offset >= size,
		.Out_Of_Bounds,
		.Error,
		"Out of bounds copy",
		"The requested memory copy operation would result in out of bounds accesses. The user specified a " +
		"copy lenth of %d, but the destination buffer (at 0x%x) has only %d bytes remaining at offset %d.",
		size,
		destination.address,
		destination_metadata.size - cast(int)destination_offset,
		destination_offset,
		location=location,
	) or_return
	_check_condition(
		source_metadata.size - cast(int)source_offset >= size,
		.Out_Of_Bounds,
		.Error,
		"Out of bounds copy",
		"The requested memory copy operation would result in out of bounds accesses. The user specified a " +
		"copy lenth of %d, but the source buffer (at 0x%x) has only %d bytes remaining at offset %d.",
		size,
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

	command := _Command_Mem_Copy {
		source		= source,
		destination	= destination,
		size		= size,
	}
	append(&metadata.commands, command)

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

	_check_condition(
		pipeline_metadata.type == .Compute,
		.Invalid_Pipeline,
		.Error,
		"Invalid pipeline type",
		"A dispatch requires a compute pipeline. The provided pipeline %v is of type %v.",
		compute_pipeline,
		pipeline_metadata.type,
		location=location,
	)

	command :=  _Command_Dispatch {
		pipeline	= compute_pipeline,
		resource_set	= metadata.resource_set,
		argument	= slice.clone(argument, metadata.allocator) or_return,
		group_count	= group_count,
	}
	append(&metadata.commands, command) or_return

	return nil
}

dispatch :: proc {
	dispatch_with_bytes_argument,
	dispatch_with_any_argument,
}

// Emplaces a synchronization barrier in the command buffer.
//
// A memory dependency is emplaced between `after` (producing) and `before` (consuming).
barrier	:: proc(
	command_buffer: Command_Buffer,
	after:		Stages,
	before:		Stages,
	location := #caller_location,
) -> Result {
	metadata, metadata_res := _metadata_of(command_buffer)
	_check_command_buffer_handle(metadata_res, command_buffer, location) or_return

	_check_condition(
		after != {} && before != {},
		.Invalid_Arguments,
		.Error,
		"Invalid `before` and `after` stages",
		"Both `after` and `before` stages must not be empty ({}).",
		location=location,
	) or_return

	command := _Command_Barrier {
		after	= after,
		before	= before,
	}
	append(&metadata.commands, command) or_return

	return nil
}

signal :: proc(command_buffer: Command_Buffer, fences: ..Fence, location := #caller_location) -> Result {
	metadata, metadata_res := _metadata_of(command_buffer)
	_check_command_buffer_handle(metadata_res, command_buffer, location) or_return

	for fence in fences {
		_, fence_res := _metadata_of(fence)
		_check_fence_handle(fence_res, fence, location) or_return
	}

	command := _Command_Signal {
		signals = slice.clone(fences, metadata.allocator) or_return,
	}
	append(&metadata.commands, command) or_return

	return nil
}

wait :: proc(command_buffer: Command_Buffer, fences: ..Fence, location := #caller_location) -> Result {
	metadata, metadata_res := _metadata_of(command_buffer)
	_check_command_buffer_handle(metadata_res, command_buffer, location) or_return

	for fence in fences {
		_, fence_res := _metadata_of(fence)
		_check_fence_handle(fence_res, fence, location) or_return
	}

	command := _Command_Wait {
		waits = slice.clone(fences, metadata.allocator) or_return,
	}
	append(&metadata.commands, command) or_return

	return nil
	
}

submit :: proc(
	queue: Queue,
	command_buffers: []Command_Buffer,
	signals: ..Semaphore_Signal,
	location := #caller_location,
) -> (res: Result) {
	
	_check_queue_validity(queue) or_return
	queue_metadata, _ := _metadata_of(queue)

	for command_buffer in command_buffers {
		command_buffer_metadata, command_buffer_res := _metadata_of(command_buffer)
		_check_command_buffer_handle(command_buffer_res, command_buffer, location) or_return

		_check_condition(
			command_buffer_metadata.queue == queue,
			.Invalid_Command_Buffer,
			.Error,
			"Invalid command buffer",
			"The command buffer %v is not related to the queue %v. It is related to the queue %v.",
			command_buffer,
			queue,
			command_buffer_metadata.queue,
		) or_return
	}

	for signal in signals {
		semaphore_metadata, semaphore_res := _metadata_of(signal.semaphore)
		_check_semaphore_handle(semaphore_res, signal.semaphore, location) or_return

		_check_condition(
			signal.value > semaphore_metadata.last_signaled_value,
			.Invalid_Arguments,
			.Error,
			"Invalid signal value",
			"The values signaled to a semaphore must be monotonically (always) increasing. The last " +
			"signaled value on semaphore %v is %d, while a signaling of %d was requested.",
			signal.semaphore,
			semaphore_metadata.last_signaled_value,
			signal.value,
			location=location,
		) or_return
	}

	_check_fence_correctness(command_buffers, location) or_return

	when TARGET_API == .Vulkan {
		res = vk_submit(queue_metadata, command_buffers, signals)
	} else {
		res = m3_submit(queue_metadata, command_buffers, signals)
	}

	_check_generic_backend_error(res, location)

	for signal in signals {
		semaphore_metadata, semaphore_res := _metadata_of(signal.semaphore)
		_check_semaphore_handle(semaphore_res, signal.semaphore, location) or_return

		semaphore_metadata.last_signaled_value = signal.value
	}

	for command_buffer in command_buffers {
		command_buffer_metadata, command_buffer_res := _metadata_of(command_buffer)
		_check_command_buffer_handle(command_buffer_res, command_buffer, location) or_return

		command_buffer_metadata.in_use = false
	}

	return res
}

_check_fence_correctness :: proc(command_buffers: []Command_Buffer, location: runtime.Source_Code_Location) -> Result {

	signaled_fences := make(map[Fence]bool, _temp_allocator)
	for command_buffer in command_buffers {
		metadata, metadata_res := _metadata_of(command_buffer)
		_check_command_buffer_handle(metadata_res, command_buffer, location) or_return

		for command in metadata.commands {
			#partial switch v in command {
			case _Command_Signal:
				for fence in v.signals {
					signaled_fences[fence] = false
				}

			case _Command_Wait:
				for fence in v.waits {
					_, is_present := signaled_fences[fence]
					_check_condition(
						is_present,
						.Invalid_Argument,
						.Error,
						"Invalid command submission order",
						"In each submission, the command buffer signaling fences must be submitted " +
						"before the one consuming them. Please note that different command buffers " +
						"working on the same set of fences must be submitted in the same call to " +
						"`gfx::submit`. Fence %v in command buffer %v was waited on before its " +
						"signaling operation.",
						command_buffer,
						fence,
						location=location,
					) or_return

					signaled_fences[fence] = true
				}
			}
		}
	}

	for fence, waited_on in signaled_fences {
		_check_generic_condition(
			waited_on,
			.Warning,
			"Fence signaled but not waited",
			"The fence %v got signaled but never waited on.",
			fence,
			location=location,
		)
	}

	return nil
}

// submit :: proc(command_buffer: Command_Buffer, location := #caller_location) {
// 	metadata, metadata_res := _metadata_of(command_buffer)
// 	_check_command_buffer_handle(metadata_res, command_buffer, location)
// 	if metadata_res != nil {
// 		return
// 	}

// 	queue_metadata, queue_res := _metadata_of(metadata.queue)
// 	assert(queue_res == nil)
	
// 	res: Result
// 	when TARGET_API == .Vulkan {
// 		res = vk_emit_commands(metadata, queue_metadata)
// 	} else {
// 		res = m3_emit_commands(metadata, queue_metadata)
// 	}

// 	_check_generic_backend_error(res, location)

// 	metadata.in_use = false
// }
// // value must be monotonically increasing.
// submit_and_signal :: proc(
// 	command_buffer: Command_Buffer,
// 	semaphore: Semaphore,
// 	value: int,
// 	location := #caller_location,
// ) {

// 	metadata, metadata_res := _metadata_of(command_buffer)
// 	_check_command_buffer_handle(metadata_res, command_buffer, location)
// 	if metadata_res != nil do return
	
// 	queue_metadata, queue_res := _metadata_of(metadata.queue)
// 	assert(queue_res == nil)
	
// 	semaphore_metadata, semaphore_res := _metadata_of(semaphore)
// 	_check_semaphore_handle(semaphore_res, semaphore, location)
// 	if semaphore_res != nil do return

// 	if value <= semaphore_metadata.last_signaled_value {
// 		_log_message(
// 			.Invalid_Arguments,
// 			.Error,
// 			"Invalid signal value",
// 			"The values signaled toxx a semaphore must be monotonically (always) increasing. The last " +
// 			"signaled value on semaphore %v is %d, while a signaling of %d was requested.",
// 			semaphore,
// 			semaphore_metadata.last_signaled_value,
// 			value,
// 		)
// 		return
// 	}

// 	command := _Command_Signal_Semaphore {
// 		semaphore	= semaphore,
// 		value		= value,
// 	}
// 	append(&metadata.commands, command)

// 	res: Result
// 	when TARGET_API == .Vulkan {
// 		res = vk_emit_commands(metadata, queue_metadata)
// 	} else {
// 		res = m3_emit_commands(metadata, queue_metadata)
// 	}
	
// 	_check_generic_backend_error(res, location)

// 	for fence in metadata.fences {
// 		destroy_fence(fence)
// 	}

// 	semaphore_metadata.last_signaled_value = value

// 	metadata.in_use = false
// }

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

