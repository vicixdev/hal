package main

import "core:log"
import "gfx"
import "core:mem"
import "core:debug/trace"

main :: proc() {
	context.logger = log.create_console_logger()
	defer log.destroy_console_logger(context.logger)

	context.assertion_failure_proc = trace.assertion_failure_proc

	tracking_allocator: trace.Tracking_Allocator
	trace.tracking_allocator_init(&tracking_allocator, context.allocator)
	defer trace.tracking_allocator_destroy(&tracking_allocator)

	context.allocator = trace.tracking_allocator(&tracking_allocator)
	defer trace.tracking_allocator_print_results(&tracking_allocator)

	gfx.init({
		vk = {
			// shader_format = .Metallib,
		},
	})
	defer gfx.fini()

	devices, _ := gfx.enumerate_devices()
	log.infof("%#v", devices)
	gfx.select_device(devices[0].id)

	chunky_boy, chunky_boy_res := gfx.alloc(.Private, 512 * mem.Gigabyte)
	log.info(chunky_boy, chunky_boy_res)

	// buffer, _ := gfx.alloc(.Default, 128 * 1024 * 1024)
	buffer, _ := gfx.alloc(.Default, 128 * 1024 * 1024 + 1)
	// buffer, _ := gfx.alloc(.Default, 128)
	defer gfx.dealloc(buffer)

	log.info(buffer, buffer.contents)

	gpu, _ := gfx.gpu_address_of(buffer)

	buffer.address += 10
	gpu2, _ := gfx.gpu_address_of(buffer)

	log.info(gpu, gpu2)

	tex_desc := gfx.Texture_Descriptor {
		type		= .Cube_Array,
		dimensions	= { 640, 640, 1 },
		mip_count	= 1,
		layer_count	= 6 * 5,
		sample_count	= 1,
		format		= .RGBA8_Unorm,
		usage		= { .Storage, .Sampled },
	}
	size, align, _ := gfx.size_align_of(tex_desc)
	log.info(size, align)

	texture_buffer, _ := gfx.alloc(.Private, 128 * 1024 * 1024)
	// texture_buffer, _ := gfx.alloc(.Private, 1024)

	tex, etex := gfx.create_texture(texture_buffer, tex_desc)
	defer gfx.destroy_texture(tex)
	v1, eview1 := gfx.default_view_of(tex)
	v2, eview2 := gfx.create_view(tex, {
		type		= .D2_Array,
		base_mip	= 0,
		mip_count	= 1,
		base_layer	= 4,
		layer_count	= 5,
	})

	log.info(tex, v1, v2, etex, eview1, eview2)

	sampler_desc := gfx.Sampler_Descriptor {
		min_filter	= .Nearest,
		mag_filter	= .Linear,
		mip_filter	= .Linear,
		address_u	= .Clamp_To_Border,
		address_v	= .Clamp_To_Border,
		address_w	= .Clamp_To_Border,
		border_color	= .Opaque_Black_Float,
		max_anisotropy	= 16,
	}
	sampler, _ := gfx.create_sampler(sampler_desc)
	defer gfx.destroy_sampler(sampler)

	bytecode, _ := gfx.load_bytecode_of("basic", "./build", context.temp_allocator)
	pipeline, pipeline_res := gfx.create_compute_pipeline(
		{
			bytecode	= bytecode,
			entrypoint	= "computeMain",
		},
		{ 1, 1, 1 },
	)
	defer gfx.destroy_pipeline(pipeline)
	log.info(pipeline, pipeline_res)

	log.info(tex, v1, v2)
	gfx.label(tex, "Texture texture")

	resource_set, _ := gfx.create_resource_set()
	defer gfx.destroy_resource_set(resource_set)

	gfx.set_texture_set(resource_set, .Cube_Array, { v1 })
	gfx.set_texture_set(resource_set, .D2_Array, { v2 })
	gfx.set_storage_texture_set(resource_set, .D2_Array, { v2 })
	gfx.set_sampler_set(resource_set, { sampler })

	for _ in 0..<1024 {
		assert(generic_compute_test() == nil)
	}

}

@(test)
generic_compute_test :: proc() -> gfx.Result {
	ARRAY_LENGTH :: 4096

	when gfx.TARGET_API == .Vulkan {
		ADD_BYTECODE := #load("./gfx/tests/shaders/basic.spv")
	} else when gfx.TARGET_API == .Metal_3 {
		ADD_BYTECODE := #load("./gfx/tests/shaders/basic.metallib")
	}

	Parameters :: struct {
		in_a:	uintptr,
		in_b:	uintptr,
		out:	uintptr,
	}

	half: f32 = 0.5
	add_pipeline := gfx.create_compute_pipeline({
		bytecode	= ADD_BYTECODE[:],
		entrypoint	= "add",
		constants	= {
			{ type = .F32, value = &half },
		},
	}, { 128, 1, 1 }) or_return

	semaphore := gfx.create_semaphore(.Cpu_Waitable) or_return

	memory: gfx.Arena
	gfx.create_arena(&memory, .Default, size_of(f32) * ARRAY_LENGTH * 3) or_return

	in_a := gfx.arena_alloc(&memory, size_of(f32) * ARRAY_LENGTH) or_return
	in_b := gfx.arena_alloc(&memory, size_of(f32) * ARRAY_LENGTH) or_return
	out := gfx.arena_alloc(&memory, size_of(f32) * ARRAY_LENGTH) or_return

	floats_a := cast([^]f32)in_a.address
	floats_b := cast([^]f32)in_b.address
	floats_out := cast([^]f32)out.address
	for i := 0; i < ARRAY_LENGTH; i += 1 {
		floats_a[i] = cast(f32)i
		floats_b[i] = cast(f32)i * 4
	}

	gpu_a := gfx.gpu_address_of(in_a) or_return
	gpu_b := gfx.gpu_address_of(in_b) or_return
	gpu_out := gfx.gpu_address_of(out) or_return

	command_buffer := gfx.begin_command_encoding(.Default) or_return
	gfx.dispatch(command_buffer, add_pipeline, Parameters {
		in_a	= gpu_a,
		in_b	= gpu_b,
		out	=  gpu_out,
	}, { ARRAY_LENGTH / 128, 1, 1 })
	gfx.submit(.Default, {command_buffer}, {semaphore, 1})

	gfx.wait_semaphore(semaphore, 1)
	for i := 0; i < ARRAY_LENGTH; i += 1 {
		assert(floats_out[i] == floats_a[i] + floats_b[i] * half)
	}

	return nil
}

