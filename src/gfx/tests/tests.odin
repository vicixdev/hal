#+private
package gfx_tests

import "core:testing"
import gfx ".."

@(test)
init_fini :: proc(t: ^testing.T) {
	init_res := gfx.init()
	testing.expect(t, init_res == nil)

	gfx.fini()
}

@(test)
supports_multi_init :: proc(t: ^testing.T) {
	init_res := gfx.init()
	testing.expect(t, init_res == nil)
	gfx.fini()

	init_res = gfx.init()
	testing.expect(t, init_res == nil)
	gfx.fini()
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

	init_res := gfx.init()
	testing.expect_value(t, init_res, nil)
	defer gfx.fini()

	devices, devices_res := gfx.enumerate_devices()
	testing.expect(t, len(devices) > 0, "No devices found?")

	device_info := &devices[0]
	device := device_info.id
	device_res := gfx.select_device(device)
	testing.expect_value(t, device_res, nil)

	half: f32 = 0.5
	add_pipeline, add_pipeline_res := gfx.create_compute_pipeline({
		bytecode	= ADD_BYTECODE[:],
		entrypoint	= "add",
		constants	= {
			{ type = .F32, value = &half },
		},
	}, { 128, 1, 1 })
	testing.expect_value(t, add_pipeline_res, nil)

	semaphore, semaphore_res := gfx.create_semaphore()
	testing.expect_value(t, semaphore_res, nil)

	memory: gfx.Arena
	memory_res := gfx.create_arena(&memory, .Default, size_of(f32) * ARRAY_LENGTH * 3)
	testing.expect_value(t, memory_res, nil)

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
	gfx.submit_and_signal(command_buffer, semaphore, 1)

	gfx.wait_semaphore(semaphore, 1)
	for i := 0; i < ARRAY_LENGTH; i += 1 {
		testing.expect_value(t, floats_out[i], floats_a[i] + floats_b[i] * half)
	}
}

