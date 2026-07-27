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

	context.allocator = back.tracking_allocator(&tracking_allocator)
	defer back.tracking_allocator_print_results(&tracking_allocator)

	gfx.init()
	defer gfx.fini()

	// buffer, _ := gfx.alloc(.Default, 128 * 1024 * 1024)
	// defer gfx.dealloc(buffer)

	// log.info(buffer, buffer.contents)

	// gpu, _ := gfx.gpu_reference_of(buffer)

	// buffer.reference += 10
	// gpu2, _ := gfx.gpu_reference_of(buffer)

	// log.info(gpu, gpu2)

	// tex_desc := gfx.Texture_Descriptor {
	// 	type = .D2,
	// 	dimensions = { 640, 480, 1 },
	// 	mip_count = 1,
	// 	layer_count = 1,
	// 	sample_count = 1,
	// 	format = .RGBA8_Unorm,
	// 	usage = .Storage,
	// }
	// _, align, _ := gfx.size_align_of(tex_desc)

	// buffer.reference = mem.align_backward_uintptr(buffer.reference, cast(uintptr)align)

	// tex, etex := gfx.create_texture(buffer, tex_desc)
	// defer gfx.destroy_texture(tex)
	// v1, eview1 := gfx.create_view(tex)
	// v2, eview2 := gfx.create_view(tex, {
	// 	format = .R32_Float,
	// 	base_mip = 0,
	// 	mip_count = 1,
	// 	base_layer = 0,
	// 	layer_count = 1,
	// })

	// log.info(tex, v1, v2, etex, eview1, eview2)

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

