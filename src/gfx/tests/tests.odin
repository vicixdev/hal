#+private
package gfx_tests

import "base:runtime"
import "core:testing"
import gfx ".."

@(init)
init_gfx :: proc "contextless" () {
	context = runtime.default_context()

	init_res := gfx.init()
	assert(init_res == nil, "Could not initialize gfx.")

	devices, devices_res := gfx.enumerate_devices()
	assert(devices_res == nil, "No suitable devices found.")

	device_info := &devices[0]
	device := device_info.id
	device_res := gfx.select_device(device)
	assert(device_res == nil, "Could not select a device.")
}

@(fini)
fini_gfx :: proc "contextless" () {
	context = runtime.default_context()
	gfx.fini()
}

@(test)
memory_transfers_with_barriers :: proc(t: ^testing.T) {
	device_info, _ := gfx.selected_device_info()

	upload, upload_res := gfx.alloc(.Staging, device_info.limits.min_allocation_size)
	gpu, gpu_res := gfx.alloc(.Private, device_info.limits.min_allocation_size)
	download, download_res := gfx.alloc(.Readback, device_info.limits.min_allocation_size)
	testing.expect(t, upload_res == nil && gpu_res == nil && download_res == nil)
	defer {
		gfx.dealloc(upload)
		gfx.dealloc(gpu)
		gfx.dealloc(download)
	}

	upload_i64 := cast([^]i64)upload.contents
	gpu_i64 := cast([^]i64)upload.contents
	download_i64 := cast([^]i64)upload.contents

	for i in 0..<device_info.limits.min_allocation_size / size_of(i64) {
		upload_i64[i] = cast(i64)i
	}

	sema, sema_res := gfx.create_semaphore(.Cpu_Waitable)
	testing.expect_value(t, sema_res, nil)
	defer gfx.destroy_semaphore(sema)

	command_buffer, command_buffer_res := gfx.begin_command_encoding(.Default)
	testing.expect_value(t, command_buffer_res, nil)

	gfx.mem_copy(command_buffer, gpu, upload, device_info.limits.min_allocation_size)
	gfx.barrier(command_buffer, { .Transfer }, { .Transfer })
	gfx.mem_copy(command_buffer, download, gpu, device_info.limits.min_allocation_size)
	gfx.submit(.Default, { command_buffer }, { sema, 1 })

	gfx.wait_semaphore(sema, 1)

	for i in 0..<device_info.limits.min_allocation_size / size_of(i64) {
		testing.expect_value(t, download_i64[i], cast(i64)i)
	}
}

@(test)
memory_transfers_with_fences :: proc(t: ^testing.T) {
	device_info, _ := gfx.selected_device_info()

	fence, fence_res := gfx.create_fence()
	testing.expect_value(t, fence_res, nil)
	defer gfx.destroy_fence(fence)

	upload, upload_res := gfx.alloc(.Staging, device_info.limits.min_allocation_size)
	gpu, gpu_res := gfx.alloc(.Private, device_info.limits.min_allocation_size)
	download, download_res := gfx.alloc(.Readback, device_info.limits.min_allocation_size)
	testing.expect(t, upload_res == nil && gpu_res == nil && download_res == nil)
	defer {
		gfx.dealloc(upload)
		gfx.dealloc(gpu)
		gfx.dealloc(download)
	}

	upload_i64 := cast([^]i64)upload.contents
	gpu_i64 := cast([^]i64)upload.contents
	download_i64 := cast([^]i64)upload.contents

	for i in 0..<device_info.limits.min_allocation_size / size_of(i64) {
		upload_i64[i] = cast(i64)i
	}

	sema, sema_res := gfx.create_semaphore(.Cpu_Waitable)
	testing.expect_value(t, sema_res, nil)
	defer gfx.destroy_semaphore(sema)

	command_buffer, command_buffer_res := gfx.begin_command_encoding(.Default)
	testing.expect_value(t, command_buffer_res, nil)

	gfx.mem_copy(command_buffer, gpu, upload, device_info.limits.min_allocation_size)
	gfx.signal(command_buffer, fence)
	testing.expect_value(t, fence_res, nil)

	gfx.wait(command_buffer, fence)
	gfx.mem_copy(command_buffer, download, gpu, device_info.limits.min_allocation_size)
	gfx.submit(.Default, {command_buffer}, {sema, 1})

	gfx.wait_semaphore(sema, 1)

	for i in 0..<device_info.limits.min_allocation_size / size_of(i64) {
		testing.expect_value(t, download_i64[i], cast(i64)i)
	}
}

@(test)
memory_transfers_with_multiple_command_buffers_and_fences :: proc(t: ^testing.T) {
	device_info, _ := gfx.selected_device_info()

	fence, fence_res := gfx.create_fence()
	testing.expect_value(t, fence_res, nil)
	defer gfx.destroy_fence(fence)

	upload, upload_res := gfx.alloc(.Staging, device_info.limits.min_allocation_size)
	gpu, gpu_res := gfx.alloc(.Private, device_info.limits.min_allocation_size)
	download, download_res := gfx.alloc(.Readback, device_info.limits.min_allocation_size)
	testing.expect(t, upload_res == nil && gpu_res == nil && download_res == nil)
	defer {
		gfx.dealloc(upload)
		gfx.dealloc(gpu)
		gfx.dealloc(download)
	}

	upload_i64 := cast([^]i64)upload.contents
	gpu_i64 := cast([^]i64)upload.contents
	download_i64 := cast([^]i64)upload.contents

	for i in 0..<device_info.limits.min_allocation_size / size_of(i64) {
		upload_i64[i] = cast(i64)i
	}

	sema, sema_res := gfx.create_semaphore(.Cpu_Waitable)
	testing.expect_value(t, sema_res, nil)
	defer gfx.destroy_semaphore(sema)

	cb1, cb1_res := gfx.begin_command_encoding(.Default)
	testing.expect_value(t, cb1_res, nil)
	cb2, cb2_res := gfx.begin_command_encoding(.Default)
	testing.expect_value(t, cb2_res, nil)

	gfx.mem_copy(cb1, gpu, upload, device_info.limits.min_allocation_size)
	gfx.signal(cb1, fence)

	gfx.wait(cb2, fence)
	gfx.mem_copy(cb2, download, gpu, device_info.limits.min_allocation_size)
	gfx.submit(.Default, {cb1, cb2}, {sema, 1})

	gfx.wait_semaphore(sema, 1)

	for i in 0..<device_info.limits.min_allocation_size / size_of(i64) {
		testing.expect_value(t, download_i64[i], cast(i64)i)
	}
}

@(test)
memory_transfers_with_multiple_command_buffers_and_semaphores :: proc(t: ^testing.T) {
	device_info, _ := gfx.selected_device_info()

	upload, upload_res := gfx.alloc(.Staging, device_info.limits.min_allocation_size)
	gpu, gpu_res := gfx.alloc(.Private, device_info.limits.min_allocation_size)
	download, download_res := gfx.alloc(.Readback, device_info.limits.min_allocation_size)
	testing.expect(t, upload_res == nil && gpu_res == nil && download_res == nil)
	defer {
		gfx.dealloc(upload)
		gfx.dealloc(gpu)
		gfx.dealloc(download)
	}

	upload_i64 := cast([^]i64)upload.contents
	gpu_i64 := cast([^]i64)upload.contents
	download_i64 := cast([^]i64)upload.contents

	for i in 0..<device_info.limits.min_allocation_size / size_of(i64) {
		upload_i64[i] = cast(i64)i
	}

	sema, sema_res := gfx.create_semaphore(.Cpu_Waitable)
	testing.expect_value(t, sema_res, nil)
	defer gfx.destroy_semaphore(sema)

	on_work_done, on_work_done_res := gfx.create_semaphore(.Cpu_Waitable)
	testing.expect_value(t, on_work_done_res, nil)
	defer gfx.destroy_semaphore(on_work_done)

	cb1, cb1_res := gfx.begin_command_encoding(.Default)
	testing.expect_value(t, cb1_res, nil)
	gfx.mem_copy(cb1, gpu, upload, device_info.limits.min_allocation_size)
	gfx.submit(.Default, { cb1 }, { sema, 1 })

	cb2, cb2_res := gfx.begin_command_encoding(.Default, { sema, 1 })
	gfx.mem_copy(cb2, download, gpu, device_info.limits.min_allocation_size)

	gfx.submit(.Default, { cb2 }, { on_work_done, 1 })

	gfx.wait_semaphore(on_work_done, 1)

	for i in 0..<device_info.limits.min_allocation_size / size_of(i64) {
		testing.expect_value(t, download_i64[i], cast(i64)i)
	}
}

@(test)
generic_compute_test :: proc(t: ^testing.T) {
	ARRAY_LENGTH :: 4096

	when gfx.TARGET_API == .Vulkan {
		ADD_BYTECODE := #load("./shaders/basic.spv")
	} else when gfx.TARGET_API == .Metal_3 {
		ADD_BYTECODE := #load("./shaders/basic.metallib")
	}

	Parameters :: struct {
		in_a:	uintptr,
		in_b:	uintptr,
		out:	uintptr,
	}

	half: f32 = 0.5
	add_pipeline, add_pipeline_res := gfx.create_compute_pipeline({
		bytecode	= ADD_BYTECODE[:],
		entrypoint	= "add",
		constants	= {
			{ type = .F32, value = &half },
		},
	}, { 128, 1, 1 })
	testing.expect_value(t, add_pipeline_res, nil)
	defer gfx.destroy_pipeline(add_pipeline)

	semaphore, semaphore_res := gfx.create_semaphore(.Cpu_Waitable)
	testing.expect_value(t, semaphore_res, nil)
	defer gfx.destroy_semaphore(semaphore)

	memory: gfx.Arena
	memory_res := gfx.create_arena(&memory, .Default, size_of(f32) * ARRAY_LENGTH * 3)
	testing.expect_value(t, memory_res, nil)
	defer gfx.destroy_arena(memory)

	in_a, in_a_res := gfx.arena_alloc(&memory, size_of(f32) * ARRAY_LENGTH)
	in_b, in_b_res := gfx.arena_alloc(&memory, size_of(f32) * ARRAY_LENGTH)
	out, out_res := gfx.arena_alloc(&memory, size_of(f32) * ARRAY_LENGTH)
	testing.expect(t, in_a_res == nil && in_b_res == nil && out_res == nil)

	floats_a := cast([^]f32)in_a.address
	floats_b := cast([^]f32)in_b.address
	floats_out := cast([^]f32)out.address
	for i := 0; i < ARRAY_LENGTH; i += 1 {
		floats_a[i] = cast(f32)i
		floats_b[i] = cast(f32)i * 4
	}

	gpu_a, gpu_a_res := gfx.gpu_address_of(in_a)
	gpu_b, gpu_b_res := gfx.gpu_address_of(in_b)
	gpu_out, gpu_out_res := gfx.gpu_address_of(out)
	testing.expect(t, gpu_a_res == nil && gpu_b_res == nil && gpu_out_res == nil)

	command_buffer, command_buffer_res := gfx.begin_command_encoding(.Default)
	testing.expect_value(t, command_buffer_res, nil)
	gfx.dispatch(command_buffer, add_pipeline, Parameters {
		in_a	= gpu_a,
		in_b	= gpu_b,
		out	=  gpu_out,
	}, { ARRAY_LENGTH / 128, 1, 1 })
	gfx.submit(.Default, {command_buffer}, {semaphore, 1})

	gfx.wait_semaphore(semaphore, 1)
	for i := 0; i < ARRAY_LENGTH; i += 1 {
		// testing.expect_value(t, floats_out[i], floats_a[i] + floats_b[i] * half)
	}
}

