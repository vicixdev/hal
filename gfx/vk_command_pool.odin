package vicixdev_gfx

/*
This Source Code Form is subject to the terms of the Mozilla Public
License, v. 2.0. If a copy of the MPL was not distributed with this
file, You can obtain one at https://mozilla.org/MPL/2.0/.
*/



import "base:runtime"
import vk "vendor:vulkan"

// Usage:
//	pool := _vk_create_command_pool() or_return
//	fence := _vk_begin_command_group(&pool)
//	cb1 := _vk_acquire_command_buffer_from(&pool)
//	cb2 := _vk_acquire_command_buffer_from(&pool)
//	// both cb1 and cb2 are related with fence
//	_vk_end_command_group(&pool)
//
//	fence2 := _vk_begin_command_group(&pool)
//	cb3 := _vk_acquire_command_buffer_from(&pool)
//	// cb3 is related with fence2
//	_vk_end_command_group(&pool)
//
//	// submit cb1 and cb2 toghether signaling fence...
//	// submit cb3 signaling fence2...
//
_vk_Command_Pool :: struct {
	allocator:			runtime.Allocator,

	command_pool:			vk.CommandPool,

	free_command_buffers:		[dynamic]vk.CommandBuffer,
	pending_command_buffers:	map[vk.Fence][]vk.CommandBuffer,

	free_fences:			[dynamic]vk.Fence,

	current_fence:			vk.Fence,
	current_command_buffers:	[dynamic]vk.CommandBuffer,
}

_vk_create_command_pool :: proc(
	queue_family: u32,
	allocator: runtime.Allocator,
) -> (pool: _vk_Command_Pool, res: Result) {

	pool_info := vk.CommandPoolCreateInfo {
		sType			= .COMMAND_POOL_CREATE_INFO,
		flags			= { .TRANSIENT, .RESET_COMMAND_BUFFER },
		queueFamilyIndex	= queue_family,
	}
	_vk_call(vk.CreateCommandPool(_vk_device, &pool_info, nil, &pool.command_pool)) or_return

	pool.free_command_buffers	= make([dynamic]vk.CommandBuffer, allocator) or_return
	pool.free_fences		= make([dynamic]vk.Fence, allocator) or_return
	pool.current_command_buffers	= make([dynamic]vk.CommandBuffer, allocator) or_return
	pool.pending_command_buffers	= make(map[vk.Fence][]vk.CommandBuffer, allocator)
	pool.allocator = allocator

	return
}

_vk_destroy_command_pool :: proc(pool: _vk_Command_Pool) {
	for fence, command_buffers in pool.pending_command_buffers {
		if len(command_buffers) > 0 {
			vk.FreeCommandBuffers(
				_vk_device,
				pool.command_pool,
				cast(u32)len(command_buffers),
				raw_data(command_buffers),
			)
		}

		if fence != pool.current_fence {
			vk.DestroyFence(_vk_device, fence, nil)
		}

		delete(command_buffers, pool.allocator)
	}
	for fence in pool.free_fences {
		vk.DestroyFence(_vk_device, fence, nil)
	}
	if len(pool.current_command_buffers) > 0 {
		vk.FreeCommandBuffers(
			_vk_device,
			pool.command_pool,
			cast(u32)len(pool.current_command_buffers),
			raw_data(pool.current_command_buffers),
		)
	}
	if len(pool.free_command_buffers) > 0 {
		vk.FreeCommandBuffers(
			_vk_device,
			pool.command_pool,
			cast(u32)len(pool.free_command_buffers),
			raw_data(pool.free_command_buffers),
		)
	}

	vk.DestroyFence(_vk_device, pool.current_fence, nil)
	vk.DestroyCommandPool(_vk_device, pool.command_pool, nil)

	delete(pool.free_command_buffers)
	delete(pool.free_fences)
	delete(pool.current_command_buffers)
	delete(pool.pending_command_buffers)
}

_vk_begin_command_group :: proc(pool: ^_vk_Command_Pool) -> (fence: vk.Fence, res: Result) {

	assert(pool.current_fence == {}, "Previous command group not closed.")

	_vk_refresh_command_buffer_pool(pool) or_return

	if len(pool.free_fences) > 0 {
		fence = pop(&pool.free_fences)
	} else {
		fence_info := vk.FenceCreateInfo {
			sType	= .FENCE_CREATE_INFO,
		}
		_vk_call(vk.CreateFence(_vk_device, &fence_info, nil, &fence)) or_return
	}

	pool.current_fence = fence

	return
}

_vk_end_command_group :: proc(pool: ^_vk_Command_Pool) {
	
	assert(pool.current_fence != {}, "Command group not opened.")

	if len(pool.current_command_buffers) != 0 {
		pool.pending_command_buffers[pool.current_fence] = pool.current_command_buffers[:]

		pool.current_command_buffers = make([dynamic]vk.CommandBuffer, pool.allocator)
	} else {
		vk.ResetFences(_vk_device, 1, &pool.current_fence)
		append(&pool.free_fences, pool.current_fence)
	}
	
	pool.current_fence = {}
}

_vk_acquire_command_buffer_from :: proc(
	pool: ^_vk_Command_Pool,
) -> (command_buffer: vk.CommandBuffer, res: Result) {

	_vk_refresh_command_buffer_pool(pool) or_return

	if len(pool.free_command_buffers) > 0 {
		command_buffer = pop(&pool.free_command_buffers)
	} else {
		command_buffer_info := vk.CommandBufferAllocateInfo {
			sType			= .COMMAND_BUFFER_ALLOCATE_INFO,
			commandBufferCount	= 1,
			commandPool		= pool.command_pool,
			level			= .PRIMARY,
		}
		_vk_call(vk.AllocateCommandBuffers(_vk_device, &command_buffer_info, &command_buffer)) or_return
	}

	append(&pool.current_command_buffers, command_buffer)

	vk.ResetCommandBuffer(command_buffer, {})

	return
}

_vk_refresh_command_buffer_pool :: proc(pool: ^_vk_Command_Pool) -> Result {

	ok_fences := make([dynamic]vk.Fence, 0, len(pool.pending_command_buffers), context.temp_allocator) or_return
	for fence in pool.pending_command_buffers {
		if vk.GetFenceStatus(_vk_device, fence) != .SUCCESS {
			continue
		}

		append(&ok_fences, fence) or_return
	}

	for &fence in ok_fences {
		_, command_buffers := delete_key(&pool.pending_command_buffers, fence)

		vk.ResetFences(_vk_device, 1, &fence)

		append(&pool.free_command_buffers, ..command_buffers) or_return
		append(&pool.free_fences, fence) or_return

		delete(command_buffers, pool.allocator)
	}

	return nil
}

