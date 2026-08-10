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

	// upload, _ := gfx.alloc(.Default, 128)
	// private, _ := gfx.alloc(.Private, 128)
	// download, _ := gfx.alloc(.Readback, 128)

	// for i in 0..<128 {
	// 	(cast([^]byte)upload.contents)[i] = cast(byte)i
	// }

	// cb, cb_res := gfx.begin_command_encoding(.Default)
	// log.info(cb_res)
	// gfx.mem_copy(cb, private, upload, 128)
	// gfx.barrier(cb, { .Transfer }, { .Transfer })
	// gfx.mem_copy(cb, download, private, 128)
	// gfx.submit(cb)

	// time.sleep(1 * 1000 * 1000 * 1000)

	// for i in 0..<128 {
	// 	log.info(i, (cast([^]byte)download.contents)[i])
	// }

	big_mult()

	// upload, _ := gfx.alloc(.Default, 128)
	// private, _ := gfx.alloc(.Private, 128)
	// download, _ := gfx.alloc(.Readback, 128)

	// for i in 0..<128 {
	// 	(cast([^]byte)upload.contents)[i] = cast(byte)i
	// }

	// cb, cb_res := gfx.begin_command_encoding(.Default)
	// log.info(cb_res)
	// gfx.mem_copy(cb, private, upload, 128)
	// gfx.barrier(cb, { .Transfer }, { .Transfer })
	// gfx.mem_copy(cb, download, private, 128)
	// gfx.submit(cb)

	// time.sleep(1 * 1000 * 1000 * 1000)

	// for i in 0..<128 {
	// 	log.info(i, (cast([^]byte)download.contents)[i])
	// }
}

big_mult :: proc() -> gfx.Result {
	Params :: struct {
		a:	uintptr,
		b:	uintptr,
		res:	uintptr,
	}

	on_work_done := gfx.create_semaphore() or_return
	defer gfx.destroy_semaphore(on_work_done)

	a := gfx.alloc(.Default, 16 * mem.Kilobyte) or_return
	b := gfx.alloc(.Default, 16 * mem.Kilobyte) or_return
	res := gfx.alloc(.Private, 16 * mem.Kilobyte) or_return
	c := gfx.alloc(.Readback, 16 * mem.Kilobyte) or_return
	
	for i in 0..<128 {
		(cast([^]f32)a.contents)[i] = cast(f32)i
		(cast([^]f32)b.contents)[i] = cast(f32)i / 4
	}

	bytecode, _ := gfx.load_bytecode_of("basic", "build", context.temp_allocator)
	pipeline := gfx.create_compute_pipeline(
		{
			entrypoint = "computeMain",
			bytecode = bytecode,
		},
		{ 1, 1, 1 },
	) or_return

	cb := gfx.begin_command_encoding(.Default) or_return
	gfx.dispatch(
		cb,
		pipeline,
		Params {
			a = gfx.gpu_address_of(a) or_return,
			b = gfx.gpu_address_of(b) or_return,
			res = gfx.gpu_address_of(res) or_return,
		},
		{ 128, 1, 1 },
	)
	gfx.barrier(cb, { .Compute }, { .Transfer })
	gfx.mem_copy(cb, c, res, 128 * size_of(f32))
	gfx.submit_and_signal(cb, on_work_done, 1)

	gfx.wait_semaphore(on_work_done, 1)
	for i in 0..<128 {
		log.info(i, (cast([^]f32)c.contents)[i])
	}

	return nil
}

