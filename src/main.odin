package main

import "core:time"
import "core:slice"
import "core:log"
import "core:mem"
import "core:debug/trace"
import la "core:math/linalg"
import sdl "vendor:sdl3"
import "gfx"

WINDOW_SIZE :: [2]int {
	1024, 768,
}

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

device_info:		gfx.Device_Info

surface:		gfx.Surface
surface_format:		gfx.Pixel_Format

default_memory:		gfx.Arena
private_memory:		gfx.Arena
frame_memory:		gfx.Scratch

vertices:		[]Vertex
gpu_vertices:		uintptr
indices:		[]u16

color_buffer:		gfx.Texture
color_buffer_view:	gfx.View
depth_buffer:		gfx.Texture
depth_buffer_view:	gfx.View
depth_format:		gfx.Pixel_Format

depth_stencil:		gfx.Depth_Stencil_State

pipeline:		gfx.Pipeline

frame_semaphore:	gfx.Semaphore
frame_count:		int

camera:			Camera
cube_rotation:		f32

setup :: proc() {
	ensure(sdl.Init({ .VIDEO }) == true)

	window_flags := sdl.WindowFlags { .RESIZABLE }
	when ODIN_OS == .Darwin {
		window_flags += { .METAL }
	}

	window_title: cstring = "Vulkan" when gfx.TARGET_API == .Vulkan else "Metal 3"
	window = sdl.CreateWindow(
		window_title,
		cast(i32)window_state.dimensions.x,
		cast(i32)window_state.dimensions.y,
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
		dimensions		= window_state.dimensions,
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

prepare_stuff_for_window_size :: proc() -> gfx.Result {
	if depth_buffer != {} {
		gfx.wait_idle(.Default)
		gfx.destroy_texture(depth_buffer)
	}
	gfx.arena_free_all(&private_memory)

	color_buffer_descriptor := gfx.Texture_Descriptor {
		type		= .D2_Array,
		dimensions	= { **window_state.dimensions, 1 },
		mip_count	= 1,
		layer_count	= 1,
		sample_count	= 4,
		format		= surface_format,
		usage		= { .Color_Attachment },
	}
	color_buffer_size, color_buffer_align := gfx.size_align_of(color_buffer_descriptor) or_return
	color_buffer_memory := gfx.arena_alloc(&private_memory, color_buffer_size, color_buffer_align) or_return
	color_buffer = gfx.create_texture(color_buffer_memory, color_buffer_descriptor) or_return
	color_buffer_view = gfx.default_view_of(color_buffer) or_return

	depth_buffer_descriptor := gfx.Texture_Descriptor {
		type		= .D2_Array,
		dimensions	= { **window_state.dimensions, 1 },
		mip_count	= 1,
		layer_count	= 1,
		sample_count	= 4,
		format		= .D32_Float,
		usage		= { .Depth_Stencil_Attachment },
	}
	depth_buffer_size, depth_buffer_align := gfx.size_align_of(depth_buffer_descriptor) or_return
	depth_buffer_memory := gfx.arena_alloc(&private_memory, depth_buffer_size, depth_buffer_align) or_return
	depth_buffer = gfx.create_texture(depth_buffer_memory, depth_buffer_descriptor) or_return
	depth_buffer_view = gfx.default_view_of(depth_buffer) or_return
	depth_format = .D32_Float

	camera.fov	= la.to_radians(cast(f32)95.0)
	camera.aspect	= cast(f32)window_state.dimensions.x / cast(f32)window_state.dimensions.y
	camera.near	= 0.01
	camera.far	= 100.0

	return nil
}

app :: proc() -> gfx.Result {

	frame_semaphore = gfx.create_semaphore(.Cpu_Waitable) or_return

	gfx.create_arena(&default_memory, .Default, 16 * mem.Megabyte) or_return
	gfx.create_arena(&private_memory, .Private, 128 * mem.Megabyte) or_return
	gfx.create_scratch(&frame_memory, .Default, 1 * mem.Megabyte) or_return

	vertices = gfx.arena_alloc(&default_memory, []Vertex, len(VERTICES)) or_return
	copy(vertices, VERTICES[:])
	gpu_vertices = gfx.gpu_address_of(raw_data(vertices)) or_return

	indices = gfx.arena_alloc(&default_memory, []u16, len(INDICES)) or_return
	copy(indices, INDICES[:])

	prepare_stuff_for_window_size()

	depth_stencil = gfx.create_depth_stencil_state(gfx.Depth_Stencil_Descriptor {
		depth_enable	= true,
		depth_write	= true,
		depth_test	= .Less,
	}) or_return

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
		sample_count	= 4,
		color_formats	= { surface_format },
		depth_format	= depth_format,
	}
	pipeline = gfx.create_render_pipeline(pipeline_descriptor) or_return

	prev_time := time.tick_now()
	delta_time: f32

	for !should_quit {
		frame_count += 1
		if frame_count > 3 {
			gfx.wait_semaphore(frame_semaphore, frame_count - 3)
		}

		process_events()

		if window_state.did_resize {
			prepare_stuff_for_window_size() or_return
			gfx.resize_surface(surface, window_state.dimensions)
		}

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

		cube_rotation += 0.25 * delta_time
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
					view		= color_buffer_view,
					resolve_view	= surface_view,
					load_operation	= .Clear,
					store_operation	= .Resolve,
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
			args^ = {
				vertices	= gpu_vertices,
				model		= la.matrix4_translate_f32({ 0.0, 0.0, -5.0}) * la.matrix4_rotate_f32(cube_rotation, { 0.0, 1.0, 0.0 }),
				view		= view,
				proj		= proj,
			}
			// TODO: Check for renderpass attachment and pipeline pixel formats compatibility
			gfx.draw_indexed(command_buffer, pipeline, args, raw_data(indices), 36) or_return
		gfx.end_render_pass(command_buffer) or_return

		gfx.submit(.Default, { command_buffer }, { frame_semaphore, frame_count }) or_return
		gfx.present(.Default, surface_view, { frame_semaphore, frame_count }) or_return
	}

	gfx.wait_semaphore(frame_semaphore, frame_count)

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

