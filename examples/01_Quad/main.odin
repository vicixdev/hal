package main

import "core:slice"
import "core:log"
import "core:mem"
import "core:debug/trace"
import "vendor:glfw"
import "../../src/gfx"

window:		glfw.WindowHandle
surface:	gfx.Surface
surface_format:	gfx.Pixel_Format

setup :: proc() {
	ensure(glfw.Init() == true)

	glfw.WindowHint(glfw.CLIENT_API, glfw.NO_API)
	glfw.WindowHint(glfw.RESIZABLE, glfw.FALSE)
	window = glfw.CreateWindow(640, 480, "Vulkan" when gfx.TARGET_API == .Vulkan else "Metal 3", nil, nil)
	assert(window != nil)

	gfx.init()

	devices, _ := gfx.enumerate_devices()
	log.infof("%#v", devices)
	device := devices[0].id

	gfx.select_device(device)

	target: gfx.Surface_Target
	when ODIN_OS == .Darwin {
		target = gfx.Surface_Cocoa_Target {
			ns_view	= glfw.GetCocoaView(window),
		}
	} else when ODIN_OS == .Windows {
		target = gfx.Surface_HWND_Target {
			h_wnd	= glfw.GetWin32Window(window),
		}
	} else {
		#panic("*nix is not yet supported.")
	}

	surface_descriptor := gfx.Surface_Descriptor {
		type			= .V_Sync,
		dimensions		= { 640, 480 },
		frames_in_flight	= 3,
		target			= target,
	}
	formats, formats_res := gfx.supported_formats_of(surface_descriptor)
	assert(formats_res == nil && len(formats) > 0)

	surface_format = formats[0]
	if slice.contains(formats, gfx.Pixel_Format.BGRA8_Unorm) {
		surface_format = .BGRA8_Unorm
	}
	surface_descriptor.format = surface_format
	log.info(formats)
	log.infof("Creating surface with descriptor %#v.", surface_descriptor)

	surface_res: gfx.Result
	surface, surface_res = gfx.create_surface(surface_descriptor)
	assert(surface_res == nil)

}

fini :: proc() {
	gfx.fini()
	glfw.Terminate()
}

app :: proc() -> gfx.Result {

	Vertex :: struct #packed {
		position:	[3]f32,
		color:		[3]f32,
	}
	VERTICES := [?]Vertex {
		{ { -0.5, -0.5, 1.0 }, { 1.0, 0.0, 0.0 } },
		{ {  0.5, -0.5, 1.0 }, { 0.0, 1.0, 0.0 } },
		{ {  0.5,  0.5, 1.0 }, { 0.0, 0.0, 1.0 } },
		{ { -0.5,  0.5, 1.0 }, { 1.0, 1.0, 0.0 } },
	}
	INDICES := [?]u16 {
		0, 1, 2,
		2, 3, 0,
	}

	Arguments :: struct #packed {
		vertices:	uintptr,
	}

	frame_semaphore := gfx.create_semaphore(.Cpu_Waitable) or_return
	framecount: int

	default_memory: gfx.Arena
	gfx.create_arena(&default_memory, .Default, 16 * mem.Megabyte) or_return

	vertices := gfx.arena_alloc(&default_memory, []Vertex, size_of(VERTICES)) or_return
	copy(vertices, VERTICES[:])
	gpu_vertices := gfx.gpu_address_of(raw_data(vertices)) or_return

	indices := gfx.arena_alloc(&default_memory, []u16, size_of(INDICES)) or_return
	copy(indices, INDICES[:])

	pipeline_bytecode, _ := gfx.load_bytecode_of("triangle", "./shaders", context.temp_allocator)
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
		sample_count	= 1,
		color_formats	= { surface_format },
	}
	pipeline := gfx.create_render_pipeline(pipeline_descriptor) or_return

	for !glfw.WindowShouldClose(window) {
		glfw.PollEvents()
		framecount += 1

		if framecount > 3 {
			gfx.wait_semaphore(frame_semaphore, framecount - 3)
		}

		surface_view: gfx.View
		for {
			surface_view_res: gfx.Result
			surface_view, surface_view_res = gfx.acquire_surface_view(surface)
			if surface_view_res == .Surface_Unavailable {
				continue
			} else if surface_view_res == nil {
				break
			} else {
				return surface_view_res
			}
		}

		render_pass_descriptor := gfx.Render_Pass_Descriptor {
			color_attachments = {
				gfx.Render_Attachment {
					view		= surface_view,
					load_operation	= .Clear,
					store_operation	= .Store,
					clear_value	= [4]f64{ 0.1, 0.025, 0.2, 1.0 },
				},
			},
		}

		command_buffer := gfx.begin_command_encoding(.Default) or_return

		gfx.begin_render_pass(command_buffer, render_pass_descriptor)
			arguments := gfx.arena_alloc(&default_memory, Arguments) or_return
			arguments^ = Arguments {
				vertices = gpu_vertices,
			}
			// TODO: Check for renderpass attachment and pipeline pixel formats compatibility
			gfx.draw_indexed(command_buffer, pipeline, arguments, raw_data(indices), 6)
		gfx.end_render_pass(command_buffer)

		gfx.submit(.Default, { command_buffer }, { frame_semaphore, framecount }) or_return
		gfx.present(.Default, surface_view, { frame_semaphore, framecount }) or_return
	}

	gfx.wait_semaphore(frame_semaphore, framecount)

	return nil
}

main :: proc() {
	context.logger = log.create_console_logger()
	defer log.destroy_console_logger(context.logger)

	context.assertion_failure_proc = trace.assertion_failure_proc

	tracking_allocator: trace.Tracking_Allocator
	trace.tracking_allocator_init(&tracking_allocator, context.allocator)
	defer trace.tracking_allocator_destroy(&tracking_allocator)

	context.allocator = trace.tracking_allocator(&tracking_allocator)
	defer trace.tracking_allocator_print_results(&tracking_allocator)

	setup()
	defer fini()

	res := app()
	if res != nil do log.fatalf("Example failed with error %v.", res)
}


