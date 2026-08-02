package gfx

import "base:runtime"
import "core:container/queue"
import vmem "core:mem/virtual"
import "core:fmt"
import "core:log"
import "core:sync"

Message_Type :: runtime.Logger_Level

Message :: struct {
	result:		Result,
	type:		Message_Type,
	failure_reason:	string,
	info_message:	string,

	location:	runtime.Source_Code_Location,
}

_message_queue:		queue.Queue(Message)
_message_queue_mutex:	sync.Mutex
_messages_arena:	vmem.Arena
_messages_allocator:	runtime.Allocator

get_message :: proc() -> (message: Message, ok: bool) {
	sync.mutex_guard(&_message_queue_mutex)

	if queue.len(_message_queue) == 0 {
		return {}, false
	}

	return queue.dequeue(&_message_queue), true
}

clear_messages :: proc() {
	vmem.arena_free_all(&_messages_arena)
}

print_messages :: proc(location := #caller_location) -> Result {
	if queue.len(_message_queue) == 0 {
		return nil
	}

	res: Result
	
	log.debugf("Gfx messanges (requested at %s:%d:%s):", location.file_path, location.line, location.procedure)
	for message in get_message() {
		if message.result != nil {
			log.logf(
				message.type,
				"\t- [%v] %s -- %s",
				message.result,
				message.failure_reason,
				message.info_message,
				location = message.location,
			)
		} else {
			log.logf(
				message.type,
				"\t- [Generic] %s -- %s",
				message.failure_reason,
				message.info_message,
				location = message.location,
			)
		}
	}

	clear_messages()
	
	return res
}

_init_messaging_system :: proc() -> Result {
	vmem.arena_init_growing(&_messages_arena) or_return
	_messages_allocator = vmem.arena_allocator(&_messages_arena)

	queue.init(&_message_queue)

	return nil
}

_fini_messaging_system :: proc() {
	vmem.arena_destroy(&_messages_arena)
	queue.destroy(&_message_queue)
}

_queue_message_struct :: proc(message: Message) {
	sync.mutex_guard(&_message_queue_mutex)

	queue.enqueue(&_message_queue, message)
}

_queue_message :: proc(
	res:		Result,
	type:		Message_Type,
	failure_reason:	string,
	info_message:	string,
	args:		..any,
	location:	runtime.Source_Code_Location = {},
) -> Result {
	_queue_message_struct({
		result		= res,
		type		= type,
		failure_reason	= failure_reason,
		info_message	= fmt.aprintf(info_message, args = args, allocator = _messages_allocator),
		location	= location,
	})

	return res
}

_queue_generic_message :: proc(
	type:		Message_Type,
	failure_reason:	string,
	info_message:	string,
	args:		..any,
	location:	runtime.Source_Code_Location = {},
) {
	_queue_message(nil, type, failure_reason, info_message, args = args, location = location)
}

_check_result :: proc(
	res:		Result,
	type:		Message_Type,
	failure_reason:	string,
	info_message:	string,
	args:		..any,
	location:	runtime.Source_Code_Location = {},
) -> Result {
	
	if res == nil {
		return nil
	}

	_queue_message(res, type, failure_reason, info_message, args=args, location=location)

	return res
}

_check_condition :: proc(
	cond:		bool,
	res:		Result,
	type:		Message_Type,
	failure_reason:	string,
	info_message:	string,
	args:		..any,
	location:	runtime.Source_Code_Location = {},
) -> Result {
	
	if cond == true {
		return nil
	}

	_queue_message(res, type, failure_reason, info_message, args=args, location=location)

	return res
}

_check_generic_condition :: proc(
	cond:		bool,
	type:		Message_Type,
	location:	runtime.Source_Code_Location,
	failure_reason:	string,
	info_message:	string,
	args:		..any,
) {
	
	if cond == true {
		return
	}

	_queue_generic_message(type, failure_reason, info_message, args=args, location=location)

	return
}

_impl :: proc(a, b: bool) -> bool {
	return !a || b
}
