package vicixdev_gfx

/*
Copyright (c) 2026 Vicix (https://github.com/vicixdev)

This Source Code Form is subject to the terms of the Mozilla Public
License, v. 2.0. If a copy of the MPL was not distributed with this
file, You can obtain one at https://mozilla.org/MPL/2.0/.
*/

import "base:intrinsics"
import "core:mem"

Arena :: struct {
	memory_type:	Memory,
	cpu_base:	uintptr,
	gpu_base:	uintptr,
	size:		int,
	offset:		int,
}

create_arena :: proc(arena: ^Arena, memory_type: Memory, size: int, location := #caller_location) -> Result {
	size := size
	if !_is_aligned(cast(uintptr)size, _device_info.limits.allocation_alignment) {
		size = mem.align_forward_int(size, _device_info.limits.allocation_alignment)
	}

	cpu_base, gpu_base := alloc(memory_type, size, location) or_return

	arena^ = {
		memory_type	= memory_type,
		cpu_base	= cast(uintptr)cpu_base,
		gpu_base	= gpu_base,
		size		= size,
	}

	return nil
}

destroy_arena :: proc(arena: Arena) {
	dealloc(arena.gpu_base)
}

arena_free_all :: proc(arena: ^Arena) {
	arena.offset = 0
}

arena_alloc_raw :: proc(arena: ^Arena, #any_int size: int, align := 128) -> (cpu_address: rawptr, gpu_address: uintptr, res: Result) {
	base_offset: int
	if !_is_aligned(cast(uintptr)arena.offset, align) {
		base_offset = mem.align_forward_int(arena.offset, align)
	} else {
		base_offset = arena.offset
	}

	if base_offset + size > arena.size {
		return nil, 0, .Out_Of_Gpu_Memory
	}

	arena.offset = base_offset + size

	if arena.cpu_base != 0 {
		cpu_address = cast(rawptr)(arena.cpu_base + cast(uintptr)base_offset)
	}
	gpu_address = arena.gpu_base + cast(uintptr)base_offset

	return
}

arena_alloc_ptr :: proc(arena: ^Arena, $T: typeid, align := 128) -> (ptr: ^T, gpu_address: uintptr, res: Result)
	where !intrinsics.type_is_slice(T) {

	address: rawptr
	address, gpu_address = arena_alloc_raw(arena, size_of(T), align) or_return

	return cast(^T)address, gpu_address, nil
}

arena_alloc_slice :: proc(arena: ^Arena, $T: typeid/[]$E, #any_int length: int, align := 128) -> (slice: []E, gpu_address: uintptr, res: Result) {
	address: rawptr
	address, gpu_address = arena_alloc_raw(arena, size_of(E) * length, align) or_return

	return mem.slice_ptr(cast(^E)address, length), gpu_address, nil
}

arena_alloc :: proc {
	arena_alloc_raw,
	arena_alloc_ptr,
	arena_alloc_slice,
}

Scratch :: struct {
	memory_type:	Memory,
	cpu_base:	uintptr,
	gpu_base:	uintptr,
	size:		int,
	offset:		int,
}

create_scratch :: proc(scratch: ^Scratch, memory_type: Memory, size: int, location := #caller_location) -> Result {
	size := size
	if !_is_aligned(cast(uintptr)size, _device_info.limits.allocation_alignment) {
		size = mem.align_forward_int(size, _device_info.limits.allocation_alignment)
	}

	cpu_base, gpu_base := alloc(memory_type, size, location) or_return

	scratch^ = {
		memory_type	= memory_type,
		cpu_base	= cast(uintptr)cpu_base,
		gpu_base	= gpu_base,
		size		= size,
	}

	return nil
}

destroy_scratch :: proc(scratch: Scratch) {
	dealloc(scratch.gpu_base)
}

scratch_alloc_raw :: proc(scratch: ^Scratch, #any_int size: int, align := 128) -> (cpu_address: rawptr, gpu_address: uintptr, res: Result) {
	if size > scratch.size {
		return nil, 0, .Out_Of_Gpu_Memory
	}

	base_offset := mem.align_forward_int(scratch.offset, align)
	if base_offset + size >= scratch.size {
		base_offset = 0
	}

	scratch.offset = base_offset + size

	if scratch.cpu_base != 0 {
		cpu_address = cast(rawptr)(scratch.cpu_base + cast(uintptr)base_offset)
	}
	gpu_address = scratch.gpu_base + cast(uintptr)base_offset

	return
}

scratch_alloc_ptr :: proc(scratch: ^Scratch, $T: typeid, align := 16) -> (ptr: ^T, res: Result)
	where !intrinsics.type_is_slice(T) {

	address: rawptr
	address, gpu_address = scratch_alloc_raw(scratch, size_of(T), align) or_return

	return cast(^T)address, gpu_address, nil
}

scratch_alloc_slice :: proc(scratch: ^Scratch, $T: typeid/[]$E, #any_int length: int, align := 16) -> (slice: []E, res: Result) {
	address: rawptr
	address, gpu_address = scratch_alloc_raw(scratch, size_of(E) * length, align) or_return

	return mem.slice_ptr(cast(^E)address, length), gpu_address, nil
}

scratch_alloc :: proc {
	scratch_alloc_raw,
	scratch_alloc_ptr,
	scratch_alloc_slice,
}

