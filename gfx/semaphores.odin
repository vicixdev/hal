/*
This Source Code Form is subject to the terms of the Mozilla Public
License, v. 2.0. If a copy of the MPL was not distributed with this
file, You can obtain one at https://mozilla.org/MPL/2.0/.
*/

package vicixdev_gfx

import "base:runtime"
import "core:sync"
import hm "core:container/handle_map"

Semaphore	:: distinct Handle

Semaphore_Type	:: enum {
	/*
	A binary semaphore. It is either signaled or unsignaled. A semaphore can only be waited on when signaled and can
	only be signaled when unsignaled.
	*/
	Default,
	/*
	A binary semaphore used for synchronization with a surface.
	*/
	Surface,
	/*
	A semaphore driven by a monotonically increasing counter. Signal operations must provide a value greater than
	the current counter value. Wait operations block until the counter reaches a specified value.
	*/
	Timeline,
	/*
	A timeline semaphore that can also be waited on by the CPU.
	*/
	Cpu,
}

_Semaphore_Metadata :: struct {
	handle:			Semaphore,
	type:			Semaphore_Type,

	// NOTE: When `.Surface` semaphore
	surface:		Surface,

	using platform:	struct #raw_union {
		vk:	vk_Semaphore_Metadata,
		m3:	m3_Semaphore_Metadata,
	},
}

_semaphores:		hm.Dynamic_Handle_Map(_Semaphore_Metadata, Semaphore)
_semaphores_mutex:	sync.RW_Mutex

create_semaphore :: proc(
	type := Semaphore_Type.Default,
	location := #caller_location,
) -> (semaphore: Semaphore, res: Result) {

	_check_condition(
		type != .Surface,
		.Invalid_Arguments,
		.Error,
		"Invalid Semaphore Type",
		"The semaphore type `.Surface` can only be used internally. To acquire a surface semaphore, please " +
		"use the `gfx::acquire_surface_view` procedure.",
		location=location,
	) or_return

	return _create_semaphore(type, location)
}

destroy_semaphore :: proc(semaphore: Semaphore, location := #caller_location) {
	metadata, metadata_res := _metadata_of(semaphore)
	_check_semaphore_handle(metadata_res, semaphore, location)
	if metadata_res != nil do return

	res: Result
	when TARGET_API == .Vulkan {
		res = vk_destroy_semaphore(metadata)
	} else when TARGET_API == .Metal_3 {
		res = m3_destroy_semaphore(metadata)
	}

	_check_generic_backend_error(res, location)

	_remove_semaphore_metadata(semaphore)
}

wait_semaphore :: proc(semaphore: Semaphore, value: int, location := #caller_location) -> Result {
	metadata, metadata_res := _metadata_of(semaphore)
	_check_semaphore_handle(metadata_res, semaphore, location) or_return

	_check_condition(
		metadata.type == .Cpu,
		.Invalid_Semaphore,
		.Error,
		"Invalid semaphore type",
		"Only semaphores with type `.Cpu` can be used for CPU-GPU synchronization. The semaphore %v is of " +
		"type %v instead.",
		semaphore,
		metadata.type,
		location=location,
	) or_return

	res: Result
	when TARGET_API == .Vulkan {
		res = vk_wait_semaphore(metadata, value)
	} else when TARGET_API == .Metal_3 {
		res = m3_wait_semaphore(metadata, value)
	}

	_check_generic_backend_error(res, location) or_return

	return nil
}

// Internal, allows creating `.Surface` semaphores
_create_semaphore :: proc(type: Semaphore_Type, location: runtime.Source_Code_Location) -> (semaphore: Semaphore, res: Result) {
	handle, metadata := _add_semaphore_metadata() or_return
	defer if res != nil do _remove_semaphore_metadata(handle)

	metadata.type = type

	when TARGET_API == .Vulkan {
		res = vk_create_semaphore(metadata, type)
	} else {
		res = m3_create_semaphore(metadata, type)
	}

	_check_generic_backend_error(res, location) or_return

	return handle, nil
}

_check_semaphore_handle :: proc(result: Result, semaphore: Semaphore, location: runtime.Source_Code_Location) -> Result {
	_check_result(
		result,
		.Warning,
		"Invalid resource handle",
		"Invalid semaphore handle (%v).",
		semaphore,
		location=location,
	) or_return
	return nil
}

_semaphore_metadata_of :: proc(semaphore: Semaphore) -> (^_Semaphore_Metadata, Result) {
	sync.shared_guard(&_semaphores_mutex)

	metadata, ok := hm.get(&_semaphores, semaphore)
	if !ok {
		return nil, .Invalid_Semaphore
	}
	
	return metadata, nil
}

_add_semaphore_metadata :: proc() -> (semaphore: Semaphore, metadata: ^_Semaphore_Metadata, res: Result) {
	sync.guard(&_semaphores_mutex)

	semaphore = hm.add(&_semaphores, _Semaphore_Metadata {}) or_return
	metadata = hm.get(&_semaphores, semaphore)

	return
}

_remove_semaphore_metadata :: proc(semaphore: Semaphore) {
	sync.guard(&_semaphores_mutex)

	hm.remove(&_semaphores, semaphore)
}

