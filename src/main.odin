package main

import "core:log"
import "gfx"
// import "core:mem"
// import "core:time"
import "shared:back"

main :: proc() {
	context.logger = log.create_console_logger()
	defer log.destroy_console_logger(context.logger)

	back.register_segfault_handler()
	context.assertion_failure_proc = back.assertion_failure_proc

	tracking_allocator: back.Tracking_Allocator
	back.tracking_allocator_init(&tracking_allocator, context.allocator)
	defer back.tracking_allocator_destroy(&tracking_allocator)

	// context.allocator = back.tracking_allocator(&tracking_allocator)
	// defer back.tracking_allocator_print_results(&tracking_allocator)

	gfx.init()
	defer gfx.fini()

	devices, _ := gfx.enumerate_devices()
	log.infof("%#v", devices)
	gfx.select_device(devices[0].id)

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
		usage		= .Storage,
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

	// gfx.print_messages()

	// upload, _ := gfx.alloc(.Default, 128)
	// gpu, _ := gfx.alloc(.Private, 128)
	// download, _ := gfx.alloc(.Readback, 128)

	// for i in 0..<128 {
	// 	(cast([^]byte)upload.contents)[i] = cast(byte)i
	// }
	// gfx.mark_as_modified(upload, 128)

	// cb, _ := gfx.start_command_encoding()
	// gfx.mem_copy(cb, gpu, upload, 128)
	// gfx.barrier(cb, { .Transfer }, { .Transfer })
	// gfx.barrier(cb, { .Compute }, { .Transfer })
	// gfx.mem_copy(cb, download, gpu, 128)
	// gfx.submit(cb)

	// time.sleep(1 * 1000 * 1000 * 1000)

	// for i in 0..<128 {
	// 	log.info(i, (cast([^]byte)download.contents)[i])
	// }
}

