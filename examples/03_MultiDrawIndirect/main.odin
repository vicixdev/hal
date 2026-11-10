package main

import "core:slice"
import "core:log"
import "core:mem"
import "core:debug/trace"
import "core:image"
import "vendor:glfw"
import "../../gfx"

Result :: union #shared_nil {
	gfx.Result,
	image.Error,
}

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
		#panic("*nix is not yet supported in this example.")
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

create_image :: proc(
	command_buffer:	gfx.Command_Buffer,
	path:		string,
	image_memory:	^gfx.Arena,
	upload_memory:	^gfx.Scratch,
) -> (texture: gfx.Texture, view: gfx.View, res: Result) {
	
	img := image.load_from_file(path, allocator=context.temp_allocator) or_return
	assert(img.depth == 8 && img.channels == 4, "Unexpected image format.")

	descriptor := gfx.Texture_Descriptor{
		type		= .D2_Array,
		dimensions	= { img.width, img.height, 1 },
		format		= .RGBA8_Unorm,
		usage		= { .Sampled },
	}
	size, align := gfx.size_align_of(descriptor) or_return

	texture_buffer := gfx.arena_alloc(image_memory, size, align) or_return
	texture = gfx.create_texture(texture_buffer, descriptor) or_return
	view = gfx.default_view_of(texture) or_return

	upload_buffer := gfx.scratch_alloc(upload_memory, []byte, len(img.pixels)) or_return
	copy(upload_buffer, img.pixels[:])
	gfx.copy_buffer_to_texture(
		command_buffer,
		gfx.gpu_address_of(raw_data(upload_buffer)) or_return,
		texture,
		gfx.Texture_Region{
			layer_count	= 1,
			origin		= 0,
			size		= { img.width, img.height, 1 },
		},
	) or_return
	
	return
}

app :: proc() -> Result {

	Vertex :: struct #packed {
		position:	[3]f32,
		uv:		[2]f32,
	}
	VERTICES := [?]Vertex {
		{ { -0.5, -0.5, 1.0 }, { 0.0, 0.0 } },
		{ {  0.5, -0.5, 1.0 }, { 1.0, 0.0 } },
		{ {  0.5,  0.5, 1.0 }, { 1.0, 1.0 } },
		{ { -0.5,  0.5, 1.0 }, { 0.0, 1.0 } },
	}
	INDICES := [?]u16 {
		0, 1, 2,
		2, 3, 0,
	}

	Arguments :: struct #packed {
		vertices:		rawptr,
		texture_indices:	[3]u32,
	}

	frame_semaphore := gfx.create_semaphore(.Cpu) or_return
	framecount: int

	default_memory: gfx.Arena
	gfx.create_arena(&default_memory, .Default, 16 * mem.Megabyte) or_return
	private_memory: gfx.Arena
	gfx.create_arena(&private_memory, .Private, 128 * mem.Megabyte) or_return

	default_scratch: gfx.Scratch
	gfx.create_scratch(&default_scratch, .Default, 16 * mem.Megabyte) or_return
	upload_scratch: gfx.Scratch
	gfx.create_scratch(&upload_scratch, .Staging, 128 * mem.Megabyte) or_return

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

	resource_set := gfx.create_resource_set() or_return

	command_buffer := gfx.begin_command_encoding(.Default) or_return
	_, view1 := create_image(command_buffer, "./textures/sand.png", &private_memory, &upload_scratch) or_return
	_, view2 := create_image(command_buffer, "./textures/bricks.png", &private_memory, &upload_scratch) or_return
	_, view3 := create_image(command_buffer, "./textures/stone.png", &private_memory, &upload_scratch) or_return
	gfx.submit(.Default, command_buffer) or_return

	sampler := gfx.create_sampler(gfx.Sampler_Descriptor{}) or_return

	gfx.set_texture_set(resource_set, .D2, { view1, view2, view3 }) or_return
	gfx.set_sampler_set(resource_set, { sampler }) or_return

	command_pool := gfx.create_indirect_command_pool(gfx.Indirect_Command_Pool_Descriptor{
		type		= .Draw,
		command_count	= 1,
		call_count	= 3,
	}) or_return

	gfx.wait_idle(.Default)
	for !glfw.WindowShouldClose(window) {
		glfw.PollEvents()
		framecount += 1

		if framecount > 3 {
			gfx.wait_semaphore(frame_semaphore, framecount - 3)
		}

		surface_view: gfx.View
		surface_semaphore: gfx.Semaphore
		for {
			surface_view_res: gfx.Result
			surface_view, surface_semaphore, surface_view_res = gfx.acquire_surface_view(surface)
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

		command_buffer = gfx.begin_command_encoding(.Default) or_return
		gfx.use_resources(command_buffer, resource_set) or_return

		arguments := gfx.scratch_alloc(&default_scratch, Arguments) or_return
		arguments^ = Arguments {
			vertices	= gpu_vertices,
			texture_indices	= { 0, 1, 2 },
		}
		parameters := gfx.scratch_alloc(&default_scratch, []gfx.Draw_Indexed_Indirect_Parameters, 3) or_return
		copy(parameters, []gfx.Draw_Indexed_Indirect_Parameters{
			{
				index_count	= 6,
				instance_count	= 1,
			},
			{
				index_count	= 6,
				instance_count	= 1,
			},
			{
				index_count	= 6,
				instance_count	= 1,
			},
		})
		indirect_command := gfx.encode_draw_indexed_indirect(
			command_buffer,
			command_pool,
			pipeline,
			gfx.gpu_address_of(arguments) or_return,
			gfx.gpu_address_of(raw_data(indices)) or_return,
			gfx.gpu_address_of(raw_data(parameters)) or_return,
			3,
		) or_return

		gfx.barrier(command_buffer, { .Indirect_Encode }, { .Vertex, .Fragment }) or_return
		gfx.begin_render_pass(command_buffer, render_pass_descriptor)
			gfx.execute_indirect(command_buffer, indirect_command)
		gfx.end_render_pass(command_buffer)

		gfx.synchronize(command_buffer, {
			wait = {
				{ surface_semaphore, 0, {} },
			},
			signal = {
				{ frame_semaphore, framecount, {} },
			},
		})
		gfx.submit(.Default, command_buffer) or_return

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

@(require)
import _ "core:image/png"
