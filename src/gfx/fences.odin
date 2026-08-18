package gfx

import "base:runtime"
import "core:sync"
import hm "core:container/handle_map"

Fence :: distinct Handle

_Fence_Metadata :: struct {
	handle:		Fence,

	using platform:	struct #raw_union {
		vk:	vk_Fence_Metadata,
		m3:	m3_Fence_Metadata,
	},
}

_fences:	hm.Dynamic_Handle_Map(_Fence_Metadata, Fence)
_fences_mutex:	sync.RW_Mutex

create_fence :: proc(location := #caller_location) -> (fence: Fence, res: Result) {
	handle, metadata := _add_fence_metadata() or_return

	when TARGET_API == .Vulkan {
		res = vk_create_fence(metadata)
	} else when TARGET_API == .Metal_3 {
		res = m3_create_fence(metadata)
	}

	_check_generic_backend_error(res, location) or_return

	return handle, nil
}

destroy_fence :: proc(fence: Fence, location := #caller_location) {
	metadata, metadata_res := _metadata_of(fence)
	_check_fence_handle(metadata_res, fence, location)
	if metadata_res != nil do return

	when TARGET_API == .Vulkan {
		vk_destroy_fence(metadata)
	} else when TARGET_API == .Metal_3 {
		m3_destroy_fence(metadata)
	}

	_remove_fence_metadata(fence)
}

_check_fence_handle :: proc(result: Result, fence: Fence, location: runtime.Source_Code_Location) -> Result {
	_check_result(
		result,
		.Warning,
		"Invalid resource handle",
		"Invalid fence handle (%v).",
		fence,
		location=location,
	) or_return
	return nil
}

_fence_metadata_of :: proc(fence: Fence) -> (^_Fence_Metadata, Result) {
	sync.shared_guard(&_fences_mutex)

	metadata, ok := hm.get(&_fences, fence)
	if !ok {
		return nil, .Invalid_Fence
	}
	
	return metadata, nil
}

_add_fence_metadata :: proc() -> (fence: Fence, metadata: ^_Fence_Metadata, res: Result) {
	sync.guard(&_fences_mutex)

	fence = hm.add(&_fences, _Fence_Metadata {}) or_return
	metadata = hm.get(&_fences, fence)

	return
}

_remove_fence_metadata :: proc(fence: Fence) {
	sync.guard(&_fences_mutex)

	hm.remove(&_fences, fence)
}

