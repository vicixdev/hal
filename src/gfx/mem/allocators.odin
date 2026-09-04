package vicixdev_gfx_mem

import "base:runtime"
import "core:mem"

Allocator :: mem.Allocator
Allocator_Error :: mem.Allocator_Error
Allocator_Mode :: mem.Allocator_Mode
Allocator_Mode_Set :: mem.Allocator_Mode_Set

free_bytes :: mem.free_bytes
zero_slice :: mem.zero_slice
is_aligned :: mem.is_aligned
align_forward :: mem.align_forward
byte_slice :: mem.byte_slice
alloc_bytes_non_zeroed :: mem.alloc_bytes_non_zeroed

DEFAULT_ALIGNMENT :: mem.DEFAULT_ALIGNMENT
Megabyte :: mem.Megabyte

/*
Scratch allocator data.
*/
Scratch :: struct {
	data:                 []byte,
	curr_offset:          int,
	prev_allocation:      rawptr,
	prev_allocation_root: rawptr,
	backup_allocator:     Allocator,
	leaked_allocations:   [dynamic][]byte,
}

/*
Scratch allocator.

The scratch allocator works in a similar way to the `Arena` allocator. The
scratch allocator has a backing buffer that is allocated in contiguous regions,
from start to end.

Each subsequent allocation will be the next adjacent region of memory in the
backing buffer. If the allocation doesn't fit into the remaining space of the
backing buffer, this allocation is put at the start of the buffer, and all
previous allocations will become invalidated.

If the allocation doesn't fit into the backing buffer as a whole, it will be
allocated using a backing allocator, and the pointer to the allocated memory
region will be put into the `leaked_allocations` array. A `Warning`-level log
message will be sent as well.

Allocations which are resized will be resized in-place if they were the last
allocation. Otherwise, they are re-allocated to avoid overwriting previous
allocations.

The `leaked_allocations` array is managed by the `context` allocator if no
`backup_allocator` is specified in `scratch_init`.
*/
@(require_results)
scratch_allocator :: proc(allocator: ^Scratch) -> Allocator {
	return Allocator{
		procedure = scratch_allocator_proc,
		data = allocator,
	}
}

/*
Initialize a scratch allocator.
*/
scratch_init :: proc(s: ^Scratch, size: int, backup_allocator := context.allocator) -> Allocator_Error {
	s.data = make_aligned([]byte, size, 2*align_of(rawptr), backup_allocator) or_return
	s.curr_offset = 0
	s.prev_allocation = nil
	s.prev_allocation_root = nil
	s.backup_allocator = backup_allocator
	s.leaked_allocations.allocator = backup_allocator
	// sanitizer.address_poison(s.data)
	return nil
}

/*
Free all data associated with a scratch allocator.

This is distinct from `scratch_free_all` in that it deallocates all memory used
to setup the allocator, as opposed to all allocations made from that space.
*/
scratch_destroy :: proc(s: ^Scratch) {
	if s == nil {
		return
	}
	for ptr in s.leaked_allocations {
		free_bytes(ptr, s.backup_allocator)
	}
	delete(s.leaked_allocations)
	// sanitizer.address_unpoison(s.data)
	delete(s.data, s.backup_allocator)
	s^ = {}
}

/*
Allocate memory from a scratch allocator.

This procedure allocates `size` bytes of memory aligned on a boundary specified
by `alignment`. The allocated memory region is zero-initialized. This procedure
returns a pointer to the allocated memory region.
*/
@(require_results)
scratch_alloc :: proc(
	s:    ^Scratch,
	size: int,
	alignment := DEFAULT_ALIGNMENT,
	loc       := #caller_location,
) -> (rawptr, Allocator_Error) {
	bytes, err := scratch_alloc_bytes(s, size, alignment, loc)
	return raw_data(bytes), err
}

/*
Allocate memory from a scratch allocator.

This procedure allocates `size` bytes of memory aligned on a boundary specified
by `alignment`. The allocated memory region is zero-initialized. This procedure
returns a slice of the allocated memory region.
*/
@(require_results)
scratch_alloc_bytes :: proc(
	s:    ^Scratch,
	size: int,
	alignment := DEFAULT_ALIGNMENT,
	loc       := #caller_location,
) -> ([]byte, Allocator_Error) {
	bytes, err := scratch_alloc_bytes_non_zeroed(s, size, alignment, loc)
	if bytes != nil {
		zero_slice(bytes)
	}
	return bytes, err
}

/*
Allocate non-initialized memory from a scratch allocator.

This procedure allocates `size` bytes of memory aligned on a boundary specified
by `alignment`. The allocated memory region is not explicitly zero-initialized.
This procedure returns a pointer to the allocated memory region.
*/
@(require_results)
scratch_alloc_non_zeroed :: proc(
	s:    ^Scratch,
	size: int,
	alignment := DEFAULT_ALIGNMENT,
	loc       := #caller_location,
) -> (rawptr, Allocator_Error) {
	bytes, err := scratch_alloc_bytes_non_zeroed(s, size, alignment, loc)
	return raw_data(bytes), err
}

/*
Allocate non-initialized memory from a scratch allocator.

This procedure allocates `size` bytes of memory aligned on a boundary specified
by `alignment`. The allocated memory region is not explicitly zero-initialized.
This procedure returns a slice of the allocated memory region.
*/
@(require_results)
scratch_alloc_bytes_non_zeroed :: proc(
	s:   ^Scratch,
	size: int,
	alignment := DEFAULT_ALIGNMENT,
	loc       := #caller_location,
) -> ([]byte, Allocator_Error) {
	if s.data == nil {
		DEFAULT_BACKING_SIZE :: 4 * Megabyte
		if !(context.allocator.procedure != scratch_allocator_proc && context.allocator.data != s) {
			panic("Cyclic initialization of the scratch allocator with itself.", loc)
		}
		scratch_init(s, DEFAULT_BACKING_SIZE)
	}
	aligned_size := size
	if alignment > 1 {
		// It is possible to do this with less bytes, but this is the
		// mathematically simpler solution, and this being a Scratch allocator,
		// we don't need to be so strict about every byte.
		aligned_size += alignment - 1
	}
	if aligned_size <= len(s.data) {
		offset := uintptr(0)
		if s.curr_offset+aligned_size <= len(s.data) {
			offset = uintptr(s.curr_offset)
		} else {
			// The allocation will cause an overflow past the boundary of the
			// space available, so reset to the starting offset.
			offset = 0
		}		start := uintptr(raw_data(s.data))
		ptr := rawptr(offset+start)
		// We keep track of the original base pointer without extra alignment
		// in order to later allow the free operation to work from that point.
		s.prev_allocation_root = ptr
		if !is_aligned(ptr, alignment) {
			ptr = align_forward(ptr, uintptr(alignment))
		}
		s.prev_allocation = ptr
		s.curr_offset = int(offset) + aligned_size
		result := byte_slice(ptr, size)
		// ensure_poisoned(result)
		// sanitizer.address_unpoison(result)
		return result, nil
	} else {
		// NOTE: No need to use `aligned_size` here, as the backup allocator will handle alignment for us.
		a := s.backup_allocator
		ptr, err := alloc_bytes_non_zeroed(size, alignment, a, loc)
		if err != nil {
			return ptr, err
		}
		append(&s.leaked_allocations, ptr)
		if logger := context.logger; logger.lowest_level <= .Warning {
			if logger.procedure != nil {
				logger.procedure(logger.data, .Warning, "mem.Scratch resorted to backup_allocator" , logger.options, loc)
			}
		}
		return ptr, err
	}
}

/*
Free memory back to the scratch allocator.

This procedure frees the memory region allocated at pointer `ptr`.

If `ptr` is not the latest allocation and is not a leaked allocation, this
operation is a no-op.
*/
scratch_free :: proc(s: ^Scratch, ptr: rawptr, loc := #caller_location) -> Allocator_Error {
	if s.data == nil {
		panic("Free on an uninitialized Scratch allocator.", loc)
	}
	if ptr == nil {
		return nil
	}
	start := uintptr(raw_data(s.data))
	end := start + uintptr(len(s.data))
	old_ptr := uintptr(ptr)
	if s.prev_allocation == ptr {
		s.curr_offset = int(uintptr(s.prev_allocation_root) - start)
		// sanitizer.address_poison(s.data[s.curr_offset:])
		s.prev_allocation = nil
		s.prev_allocation_root = nil
		return nil
	}
	if start <= old_ptr && old_ptr < end {
		// NOTE(bill): Cannot free this pointer but it is valid
		return nil
	}
	if len(s.leaked_allocations) != 0 {
		for data, i in s.leaked_allocations {
			ptr := raw_data(data)
			if ptr == ptr {
				free_bytes(data, s.backup_allocator, loc)
				ordered_remove(&s.leaked_allocations, i, loc)
				return nil
			}
		}
	}
	return .Invalid_Pointer
}

/*
Free all memory back to the scratch allocator.
*/
scratch_free_all :: proc(s: ^Scratch, loc := #caller_location) {
	s.curr_offset = 0
	s.prev_allocation = nil
	for ptr in s.leaked_allocations {
		free_bytes(ptr, s.backup_allocator, loc)
	}
	clear(&s.leaked_allocations)
	// sanitizer.address_poison(s.data)
}

/*
Resize an allocation owned by a scratch allocator.

This procedure resizes a memory region defined by its location `old_memory`
and its size `old_size` to have a size `size` and alignment `alignment`. The
newly allocated memory, if any, is zero-initialized.

If `old_memory` is `nil`, this procedure acts just like `scratch_alloc()`,
allocating a memory region `size` bytes in size, aligned on a boundary specified
by `alignment`.

If `size` is 0, this procedure acts just like `scratch_free()`, freeing the
memory region located at an address specified by `old_memory`.

This procedure returns the pointer to the resized memory region.
*/
@(require_results)
scratch_resize :: proc(
	s:          ^Scratch,
	old_memory: rawptr,
	old_size:   int,
	size:       int,
	alignment := DEFAULT_ALIGNMENT,
	loc       := #caller_location
) -> (rawptr, Allocator_Error) {
	bytes, err := scratch_resize_bytes(s, byte_slice(old_memory, old_size), size, alignment, loc)
	return raw_data(bytes), err
}

/*
Resize an allocation owned by a scratch allocator.

This procedure resizes a memory region specified by `old_data` to have a size
`size` and alignment `alignment`. The newly allocated memory, if any, is
zero-initialized.

If `old_memory` is `nil`, this procedure acts just like `scratch_alloc()`,
allocating a memory region `size` bytes in size, aligned on a boundary specified
by `alignment`.

If `size` is 0, this procedure acts just like `scratch_free()`, freeing the
memory region located at an address specified by `old_memory`.

This procedure returns the slice of the resized memory region.
*/
@(require_results)
scratch_resize_bytes :: proc(
	s:        ^Scratch,
	old_data: []byte,
	size:     int,
	alignment := DEFAULT_ALIGNMENT,
	loc       := #caller_location
) -> ([]byte, Allocator_Error) {
	bytes, err := scratch_resize_bytes_non_zeroed(s, old_data, size, alignment, loc)
	if bytes != nil && size > len(old_data) {
		zero_slice(bytes[size:])
	}
	return bytes, err
}

/*
Resize an allocation owned by a scratch allocator, without zero-initialization.

This procedure resizes a memory region defined by its location `old_memory`
and its size `old_size` to have a size `size` and alignment `alignment`. The
newly allocated memory, if any, is not explicitly zero-initialized.

If `old_memory` is `nil`, this procedure acts just like `scratch_alloc()`,
allocating a memory region `size` bytes in size, aligned on a boundary specified
by `alignment`.

If `size` is 0, this procedure acts just like `scratch_free()`, freeing the
memory region located at an address specified by `old_memory`.

This procedure returns the pointer to the resized memory region.
*/
@(require_results)
scratch_resize_non_zeroed :: proc(
	s:          ^Scratch,
	old_memory: rawptr,
	old_size:   int,
	size:       int,
	alignment := DEFAULT_ALIGNMENT,
	loc       := #caller_location
) -> (rawptr, Allocator_Error) {
	bytes, err := scratch_resize_bytes_non_zeroed(s, byte_slice(old_memory, old_size), size, alignment, loc)
	return raw_data(bytes), err
}

/*
Resize an allocation owned by a scratch allocator.

This procedure resizes a memory region specified by `old_data` to have a size
`size` and alignment `alignment`. The newly allocated memory, if any, is not
explicitly zero-initialized.

If `old_memory` is `nil`, this procedure acts just like `scratch_alloc()`,
allocating a memory region `size` bytes in size, aligned on a boundary specified
by `alignment`.

If `size` is 0, this procedure acts just like `scratch_free()`, freeing the
memory region located at an address specified by `old_memory`.

This procedure returns the slice of the resized memory region.
*/
@(require_results)
scratch_resize_bytes_non_zeroed :: proc(
	s:        ^Scratch,
	old_data: []byte,
	size:     int,
	alignment := DEFAULT_ALIGNMENT,
	loc       := #caller_location
) -> ([]byte, Allocator_Error) {
	old_memory := raw_data(old_data)
	old_size := len(old_data)
	if s.data == nil {
		DEFAULT_BACKING_SIZE :: 4 * Megabyte
		if !(context.allocator.procedure != scratch_allocator_proc && context.allocator.data != s) {
			panic("Cyclic initialization of the scratch allocator with itself.", loc)
		}
		scratch_init(s, DEFAULT_BACKING_SIZE)
	}
	begin   := uintptr(raw_data(s.data))
	end     := begin + uintptr(len(s.data))
	old_ptr := uintptr(old_memory)
	// We can only sanely resize the last allocation; to do otherwise may
	// overwrite memory that could very well just have been allocated.
	//
	// Also, the alignments must match, otherwise we must re-allocate to
	// guarantee the user's request.
	if s.prev_allocation == old_memory && is_aligned(old_memory, alignment) && old_ptr+uintptr(size) < end {
		// ensure_not_poisoned(old_data)
		// sanitizer.address_poison(old_memory)
		s.curr_offset = int(old_ptr-begin)+size
		result := byte_slice(old_memory, size)
		// sanitizer.address_unpoison(result)
		return result, nil
	}
	data, err := scratch_alloc_bytes_non_zeroed(s, size, alignment, loc)
	if err != nil {
		return data, err
	}
	runtime.copy(data, byte_slice(old_memory, old_size))
	err = scratch_free(s, old_memory, loc)
	return data, err
}

scratch_allocator_proc :: proc(
	allocator_data:  rawptr,
	mode:            Allocator_Mode,
	size, alignment: int,
	old_memory:      rawptr,
	old_size:        int,
	loc := #caller_location,
) -> ([]byte, Allocator_Error) {
	s := (^Scratch)(allocator_data)
	size := size
	switch mode {
	case .Alloc:
		return scratch_alloc_bytes(s, size, alignment, loc)
	case .Alloc_Non_Zeroed:
		return scratch_alloc_bytes_non_zeroed(s, size, alignment, loc)
	case .Free:
		return nil, scratch_free(s, old_memory, loc)
	case .Free_All:
		scratch_free_all(s, loc)
	case .Resize:
		return scratch_resize_bytes(s, byte_slice(old_memory, old_size), size, alignment, loc)
	case .Resize_Non_Zeroed:
		return scratch_resize_bytes_non_zeroed(s, byte_slice(old_memory, old_size), size, alignment, loc)
	case .Query_Features:
		set := (^Allocator_Mode_Set)(old_memory)
		if set != nil {
			set^ = {.Alloc, .Alloc_Non_Zeroed, .Free, .Free_All, .Resize, .Resize_Non_Zeroed, .Query_Features}
		}
		return nil, nil
	case .Query_Info:
		return nil, .Mode_Not_Implemented
	}
	return nil, nil
}

