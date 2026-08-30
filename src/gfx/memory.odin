package gfx

import "core:mem"

Arena :: struct {
	memory_type:	Memory,
	base:		Buffer,
	size:		int,
	offset:		int,
}

create_arena :: proc(arena: ^Arena, memory_type: Memory, size: int, location := #caller_location) -> Result {
	size := size
	if !_is_aligned(cast(uintptr)size, _device_info.limits.allocation_alignment) {
		size = mem.align_forward_int(size, _device_info.limits.allocation_alignment)
	}

	buffer := alloc(memory_type, size, location) or_return

	arena.memory_type = memory_type
	arena.base	= buffer
	arena.size	= size

	return nil
}

destroy_arena :: proc(arena: Arena) {
	dealloc(arena.base)
}

arena_free_all :: proc(arena: ^Arena) {
	arena.offset = 0
}

arena_alloc :: proc(arena: ^Arena, size: int, align := 1) -> (buffer: Buffer, res: Result) {
	base_offset: int
	if !_is_aligned(cast(uintptr)arena.offset, align) {
		base_offset = mem.align_forward_int(arena.offset, align)
	} else {
		base_offset = arena.offset
	}

	if base_offset + size > arena.size {
		return {}, .Out_Of_Gpu_Memory
	}

	arena.offset = base_offset + size

	buffer = arena.base
	buffer.address += cast(uintptr)base_offset

	return
}

Scratch :: struct {
	memory_type:	Memory,
	base:		Buffer,
	size:		int,
	offset:		int,
}

create_scratch :: proc(scratch: ^Scratch, memory_type: Memory, size: int, location := #caller_location) -> Result {
	buffer := alloc(memory_type, size, location) or_return

	scratch.memory_type = memory_type
	scratch.base	= buffer
	scratch.size	= size

	return nil
}

destroy_scratch :: proc(scratch: Scratch) {
	dealloc(scratch.base)
}

scratch_alloc :: proc(scratch: ^Scratch, size: int, align := 1) -> (buffer: Buffer, res: Result) {
	if size > scratch.size {
		return {}, .Out_Of_Gpu_Memory
	}

	base_offset := mem.align_forward_int(scratch.offset, align)
	if base_offset + size >= scratch.size {
		base_offset = 0
	}

	scratch.offset = base_offset + size

	buffer = scratch.base
	buffer.address += cast(uintptr)base_offset

	return
}

