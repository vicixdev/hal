package vicixdev_gfx

import "base:runtime"
import "core:fmt"
import "core:log"

Message_Type :: runtime.Logger_Level

_log_message :: proc(
	result:		Result,
	type:		Message_Type,
	failure_reason:	string,
	info_message:	string,
	args:		..any,
	location:	runtime.Source_Code_Location = {},
) -> Result {
	location := location
	if location == {} {
		location.file_path	= "unknown"
		location.procedure	= "unknown"
		location.column		= 0
		location.line		= 0
	}

	format: string
	if result != nil {
		format = fmt.aprintf(
			"[%v] %s -- %s",
			result,
			failure_reason,
			info_message,
			allocator=_temp_allocator,
		)
	} else {
		format = fmt.aprintf(
			"[Generic] %s -- %s",
			failure_reason,
			info_message,
			allocator=_temp_allocator,
		)
	}

	log.logf(
		type,
		format,
		args=args,
		location=location,
	)

	return result
}

_log_generic_message :: proc(
	type:		Message_Type,
	failure_reason:	string,
	info_message:	string,
	args:		..any,
	location:	runtime.Source_Code_Location = {},
) {
	_log_message(nil, type, failure_reason, info_message, args = args, location=location)
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

	_log_message(res, type, failure_reason, info_message, args=args, location=location)

	return res
}

_check_specific_result :: proc(
	res:		Result,
	check:		Result,
	type:		Message_Type,
	failure_reason:	string,
	info_message:	string,
	args:		..any,
	location:	runtime.Source_Code_Location = {},
) -> Result {
	
	if res != check {
		return nil
	}

	_log_message(res, type, failure_reason, info_message, args=args, location=location)

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

	_log_message(res, type, failure_reason, info_message, args=args, location=location)

	return res
}

_check_generic_condition :: proc(
	cond:		bool,
	type:		Message_Type,
	failure_reason:	string,
	info_message:	string,
	args:		..any,
	location:	runtime.Source_Code_Location = {},
) {
	
	if cond == true {
		return
	}

	_log_generic_message(type, failure_reason, info_message, args=args, location=location)

	return
}

_impl :: proc(a, b: bool) -> bool {
	return !a || b
}

