package main

import "core:log"
import "core:mem"
import "core:debug/trace"
import "vendor:stb/image"
import "gfx"

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
	device := devices[0].id
	when gfx.TARGET_API == .Vulkan {
		for device_info in devices {
			if device_info.driver == "KosmicKrisp" {
				device = device_info.id
				break
			}
		}
	}

	gfx.select_device(device)

	default_memory: gfx.Arena
	gfx.create_arena(&default_memory, .Default, 16 * mem.Megabyte)

	private_memory: gfx.Arena
	gfx.create_arena(&private_memory, .Private, 16 * mem.Megabyte)

	Vertex :: struct #packed {
		position:	[3]f32,
		color:		[3]f32,
	}
	VERTICES := [?]Vertex {
		{ { -0.5, -0.5, 1.0 }, { 1.0, 0.0, 0.0 } },
		{ {  0.5, -0.5, 1.0 }, { 0.0, 1.0, 0.0 } },
		{ {  0.0,  0.5, 1.0 }, { 0.0, 0.0, 1.0 } },
	}
	vertices, _ := gfx.arena_alloc(&default_memory, size_of(VERTICES))
	mem.copy(vertices.contents, &VERTICES[0], size_of(VERTICES))
	gpu_vertices, _ := gfx.gpu_address_of(vertices)

	download, _ := gfx.arena_alloc(&default_memory, size_of([4]u8) * 640 * 480)

	pipeline_bytecode, _ := gfx.load_bytecode_of("triangle", "./src/gfx/tests/shaders", context.temp_allocator)
	pipeline_descriptor := gfx.Render_Pipeline_Descriptor {
		vertex_stage	= {
			bytecode	= pipeline_bytecode,
			entrypoint	= "vertex_main",
		},
		fragment_stage	= {
			bytecode	= pipeline_bytecode,
			entrypoint	= "fragment_main",
		},
		topology	= .Triangle_List,
		cull		= .None,
		sample_count	= 4,
		color_formats	= { .RGBA8_Unorm },
	}
	pipeline, _ := gfx.create_render_pipeline(pipeline_descriptor)
	defer gfx.destroy_pipeline(pipeline)

	framebuffer_descriptor := gfx.Texture_Descriptor {
		type		= .D2_Array,
		format		= .RGBA8_Unorm,
		dimensions	= { 640, 480, 1 },
		usage		= { .Color_Attachment },
	}
	framebuffer_size, framebuffer_align, _ := gfx.size_align_of(framebuffer_descriptor)
	framebuffer_memory, _ := gfx.arena_alloc(&private_memory, framebuffer_size, framebuffer_align)
	framebuffer, _ := gfx.create_texture(framebuffer_memory, framebuffer_descriptor)
	defer gfx.destroy_texture(framebuffer)
	framebuffer_view, _ := gfx.default_view_of(framebuffer)

	semaphore, _ := gfx.create_semaphore(.Cpu_Waitable)
	defer gfx.destroy_semaphore(semaphore)

	Parameters :: struct #packed {
		vertices:	uintptr,
	}

	render_pass_descriptor := gfx.Render_Pass_Descriptor {
		color_attachments = {
			gfx.Render_Attachment {
				view		= framebuffer_view,
				load_operation	= .Clear,
				store_operation	= .Store,
				clear_value	= [4]f64{ 0.1, 0.025, 0.2, 1.0 },
			},
		},
	}
	command_buffer, _ := gfx.begin_command_encoding(.Default)
	gfx.begin_render_pass(command_buffer, render_pass_descriptor)
	gfx.draw(command_buffer, pipeline, Parameters {
		vertices = gpu_vertices,
	}, 3)
	gfx.end_render_pass(command_buffer)

	gfx.barrier(command_buffer, { .Color_Attachment }, { .Transfer })
	gfx.copy_texture_to_buffer(command_buffer, framebuffer, gfx.Texture_Region {
		layer_count = 1,
		size = { 640, 480, 1 },
	}, download)

	gfx.submit(.Default, { command_buffer }, { semaphore, 1 })
	gfx.wait_semaphore(semaphore, 1)

	image.write_png("build/out.png", 640, 480, 4, download.contents, 640 * size_of([4]u8))
}

