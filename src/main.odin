package main

import "core:time"
import "core:slice"
import "core:log"
import "core:mem"
import "core:debug/trace"
import la "core:math/linalg"
import sdl "vendor:sdl3"
import "gfx"

surface:	gfx.Surface
surface_format:	gfx.Pixel_Format

WINDOW_SIZE :: [2]int {
	1024, 768,
}

Camera :: struct {
	position:	[3]f32,
	// pitch and yaw
	rotation:	[2]f32,

	fov:		f32,
	aspect:		f32,
	near:		f32,
	far:		f32,
}

// Minecraft style
move_camera :: proc(camera: ^Camera, direction: [3]f32, speed: f32, dt: f32) {
	if direction == { 0, 0, 0 } {
		return
	}

	input := la.normalize(direction) * speed * dt

	front := [3]f32 {
		la.sin(camera.rotation.y),
		0,
		-la.cos(camera.rotation.y),
	}

	right := la.cross(front, [3]f32{ 0, 1, 0})
	
	camera.position += front * input.z
	camera.position += right * input.x
	camera.position.y += input.y
}

rotate_camera :: proc(camera: ^Camera, rotation: [2]f32) {
	epsilon: f32 = 0.05

	camera.rotation += rotation

	if camera.rotation.x >= (la.PI/2 - epsilon) {
		camera.rotation.x = la.PI/2 - epsilon
	} else if camera.rotation.x <= -(la.PI/2 - epsilon) {
		camera.rotation.x = -(la.PI/2 - epsilon)
	}
}

get_camera_matrices :: proc(camera: Camera) -> (view: matrix[4,4]f32, proj: matrix[4,4]f32) {
	look_direction := [3]f32 {
		 la.cos(camera.rotation.x) * la.sin(camera.rotation.y),
		 la.sin(camera.rotation.x),
		-la.cos(camera.rotation.x) * la.cos(camera.rotation.y),
	}

	view = la.matrix4_look_at_f32(camera.position, camera.position + look_direction, { 0, 1, 0 })
	proj = la.matrix4_perspective_f32(camera.fov, camera.aspect, camera.near, camera.far)

	return
}

setup :: proc() {
	ensure(sdl.Init({ .VIDEO }) == true)

	window_flags: sdl.WindowFlags = {} when ODIN_OS != .Darwin else { .METAL }
	window_title: cstring = "Vulkan" when gfx.TARGET_API == .Vulkan else "Metal 3"
	window = sdl.CreateWindow(
		window_title,
		cast(i32)WINDOW_SIZE.x,
		cast(i32)WINDOW_SIZE.y,
		window_flags,
	)
	assert(window != nil)

	gfx.init()

	devices, _ := gfx.enumerate_devices()
	log.infof("%#v", devices)
	device := devices[0].id

	gfx.select_device(device)

	target: gfx.Surface_Target
	when ODIN_OS == .Darwin {
		target = gfx.Surface_Cocoa_Target {
			ns_view	= sdl.Metal_CreateView(window),
		}
	} else when ODIN_OS == .Windows {
		target = gfx.Surface_HWND_Target {
			h_wnd	= sdl.GetPointerProperty(sdl3.GetWindowProperties(window), sdl.PROP_WINDOW_WIN32_HWND_POINTER, nil),
		}
	} else {
		#panic("*nix is not yet supported.")
	}

	surface_descriptor := gfx.Surface_Descriptor {
		type			= .V_Sync,
		dimensions		= WINDOW_SIZE,
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

	sdl.Quit()
}

app :: proc() -> gfx.Result {

	Vertex :: struct #packed {
		position:	[3]f32,
		color:		[3]f32,
	}

	VERTICES := [?]Vertex {
		{ { -1.0, -1.0, -1.0 }, { 1.0, 0.0, 0.0 } },
		{ {  1.0, -1.0, -1.0 }, { 0.0, 1.0, 0.0 } },
		{ {  1.0,  1.0, -1.0 }, { 0.0, 0.0, 1.0 } },
		{ { -1.0,  1.0, -1.0 }, { 1.0, 1.0, 0.0 } },

		{ { -1.0, -1.0,  1.0 }, { 1.0, 0.0, 1.0 } },
		{ {  1.0, -1.0,  1.0 }, { 0.0, 1.0, 1.0 } },
		{ {  1.0,  1.0,  1.0 }, { 1.0, 1.0, 1.0 } },
		{ { -1.0,  1.0,  1.0 }, { 0.0, 0.0, 0.0 } },
	}

	INDICES := [?]u16 {
		// Front
		4, 5, 6,
		6, 7, 4,

		// Back
		0, 2, 1,
		2, 0, 3,

		// Left
		0, 4, 7,
		7, 3, 0,

		// Right
		1, 2, 6,
		6, 5, 1,

		// Top
		3, 7, 6,
		6, 2, 3,

		// Bottom
		0, 1, 5,
		5, 4, 0,
	}

	Arguments :: struct #packed {
		model:		matrix[4,4]f32,
		view:		matrix[4,4]f32,
		proj:		matrix[4,4]f32,

		vertices:	uintptr,
	}

	frame_semaphore := gfx.create_semaphore(.Cpu_Waitable) or_return
	framecount: int

	default_memory: gfx.Arena
	gfx.create_arena(&default_memory, .Default, 16 * mem.Megabyte) or_return

	private_memory: gfx.Arena
	gfx.create_arena(&private_memory, .Private, 16 * mem.Megabyte) or_return

	frame_memory: gfx.Scratch
	gfx.create_scratch(&frame_memory, .Default, 1 * mem.Megabyte) or_return

	vertices := gfx.arena_alloc(&default_memory, size_of(VERTICES)) or_return
	mem.copy(vertices.contents, &VERTICES[0], size_of(VERTICES))
	gpu_vertices := gfx.gpu_address_of(vertices) or_return

	indices := gfx.arena_alloc(&default_memory, size_of(INDICES)) or_return
	mem.copy(indices.contents, &INDICES[0], size_of(INDICES))

	depth_stencil := gfx.create_depth_stencil_state(gfx.Depth_Stencil_Descriptor {
		depth_enable	= true,
		depth_write	= true,
		depth_test	= .Less,
	}) or_return

	depth_buffer_descriptor := gfx.Texture_Descriptor {
		type		= .D2_Array,
		dimensions	= { **WINDOW_SIZE, 1 },
		mip_count	= 1,
		layer_count	= 1,
		sample_count	= 1,
		format		= .D32_Float,
		usage		= { .Depth_Stencil_Attachment },
	}
	depth_buffer_size, depth_buffer_align := gfx.size_align_of(depth_buffer_descriptor) or_return
	depth_buffer_memory := gfx.arena_alloc(&private_memory, depth_buffer_size, depth_buffer_align) or_return
	depth_buffer := gfx.create_texture(depth_buffer_memory, depth_buffer_descriptor) or_return
	depth_buffer_view := gfx.default_view_of(depth_buffer) or_return

	pipeline_bytecode, _ := gfx.load_bytecode_of("basic", "./build", context.temp_allocator)
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
		depth_format	= depth_buffer_descriptor.format,
	}
	pipeline := gfx.create_render_pipeline(pipeline_descriptor) or_return

	prev_time := time.tick_now()
	delta_time: f32

	camera := Camera {
		fov		= 95 * la.DEG_PER_RAD,
		aspect		= cast(f32)WINDOW_SIZE.x / cast(f32)WINDOW_SIZE.y,
		near		= 0.01,
		far		= 100.0,
	}
	rotation: f32

	for !should_quit {
		framecount += 1
		if framecount > 3 {
			gfx.wait_semaphore(frame_semaphore, framecount - 3)
		}

		process_events()

		time_now := time.tick_now()
		time_diff := time.tick_diff(prev_time, time_now)

		delta_time = cast(f32)time_diff / 1000_000_000
		prev_time = time_now

		if .Just_Pressed in key_states[.Tab] {
			toggle_mouse_capture()
		}
		if .Just_Pressed in key_states[.Escape] {
			should_quit = true
		}

		rotation += 0.25 * delta_time
		input := [3]f32{}
		speed: f32 = 3.0
		if .Pressed in key_states[.W] {
			input.z += 1
		} else if .Pressed in key_states[.S] {
			input.z -= 1
		}
		if .Pressed in key_states[.D] {
			input.x += 1
		} else if .Pressed in key_states[.A] {
			input.x -= 1
		}
		if .Pressed in key_states[.Space] {
			input.y += 1
		} else if .Pressed in key_states[.Left_Control] {
			input.y -= 1
		}
		if .Pressed in key_states[.Left_Shift] {
			speed = 10.0
		}
		move_camera(&camera, input, speed, delta_time)
		log.info(camera.position, delta_time)

		if mouse_state.captured || .Pressed in mouse_state.buttons[.Right] {
			camera_rotation := mouse_state.delta / 500.0
			camera_rotation.x, camera_rotation.y = camera_rotation.y, camera_rotation.x
			camera_rotation.x *= -1
			rotate_camera(&camera, camera_rotation)
		}

		view, proj := get_camera_matrices(camera)

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
			depth_attachment = gfx.Render_Attachment {
				view		= depth_buffer_view,
				load_operation	= .Clear,
				store_operation	= .Store,
				clear_value	= cast(f64)1.0,
			},
		}

		command_buffer := gfx.begin_command_encoding(.Default) or_return

		gfx.begin_render_pass(command_buffer, render_pass_descriptor)
			gfx.use_depth_stencil_state(command_buffer, depth_stencil) or_return
			args := gfx.scratch_alloc(&frame_memory, Arguments, 16) or_return
			args.contents^ = {
				vertices	= gpu_vertices,
				model		= la.matrix4_translate_f32({ 0.0, 0.0, -5.0}) * la.matrix4_rotate_f32(rotation, { 0.0, 1.0, 0.0 }),
				view		= view,
				proj		= proj,
			}
			// TODO: Check for renderpass attachment and pipeline pixel formats compatibility
			gfx.draw_indexed(command_buffer, pipeline, args, indices, 36)
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

