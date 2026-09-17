package main

import ui "shared:clay"
import "core:time"
import "core:slice"
import "core:fmt"
import "core:log"
import "core:mem"
import "core:strings"
import "core:debug/trace"
import la "core:math/linalg"
import sdl "vendor:sdl3"
import "vendor:stb/image"
import "root:gfx"

WINDOW_SIZE :: [2]int {
	1024, 768,
}

Color_Vertex :: struct #packed {
	position:	[3]f32,
	color:		[4]f32,
}

Textured_Vertex :: struct #packed {
	position:	[3]f32,
	uv:		[2]f32,
}

COLOR_VERTICES := [?]Color_Vertex {
	{ { -1.0, -1.0, -1.0 }, { 1.0, 0.0, 0.0, 0.2 } },
	{ {  1.0, -1.0, -1.0 }, { 0.0, 1.0, 0.0, 0.4 } },
	{ {  1.0,  1.0, -1.0 }, { 0.0, 0.0, 1.0, 0.6 } },
	{ { -1.0,  1.0, -1.0 }, { 1.0, 1.0, 0.0, 0.8 } },

	{ { -1.0, -1.0,  1.0 }, { 1.0, 0.0, 1.0, 0.8 } },
	{ {  1.0, -1.0,  1.0 }, { 0.0, 1.0, 1.0, 0.4 } },
	{ {  1.0,  1.0,  1.0 }, { 1.0, 1.0, 1.0, 0.6 } },
	{ { -1.0,  1.0,  1.0 }, { 0.0, 0.0, 0.0, 0.2 } },
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

TEXTURED_VERTICES := [?]Textured_Vertex {
	// Front
	{ { -1.0, -1.0,  1.0 }, { 0.0, 0.0 } },
	{ {  1.0, -1.0,  1.0 }, { 1.0, 0.0 } },
	{ {  1.0,  1.0,  1.0 }, { 1.0, 1.0 } },
	{ { -1.0,  1.0,  1.0 }, { 0.0, 1.0 } },

	// Back
	{ {  1.0, -1.0, -1.0 }, { 0.0, 0.0 } },
	{ { -1.0, -1.0, -1.0 }, { 1.0, 0.0 } },
	{ { -1.0,  1.0, -1.0 }, { 1.0, 1.0 } },
	{ {  1.0,  1.0, -1.0 }, { 0.0, 1.0 } },

	// Left
	{ { -1.0, -1.0, -1.0 }, { 0.0, 0.0 } },
	{ { -1.0, -1.0,  1.0 }, { 1.0, 0.0 } },
	{ { -1.0,  1.0,  1.0 }, { 1.0, 1.0 } },
	{ { -1.0,  1.0, -1.0 }, { 0.0, 1.0 } },

	// Right
	{ { 1.0, -1.0,  1.0 }, { 0.0, 0.0 } },
	{ { 1.0, -1.0, -1.0 }, { 1.0, 0.0 } },
	{ { 1.0,  1.0, -1.0 }, { 1.0, 1.0 } },
	{ { 1.0,  1.0,  1.0 }, { 0.0, 1.0 } },

	// Top
	{ { -1.0,  1.0,  1.0 }, { 0.0, 0.0 } },
	{ {  1.0,  1.0,  1.0 }, { 1.0, 0.0 } },
	{ {  1.0,  1.0, -1.0 }, { 1.0, 1.0 } },
	{ { -1.0,  1.0, -1.0 }, { 0.0, 1.0 } },

	// Bottom
	{ { -1.0, -1.0, -1.0 }, { 0.0, 0.0 } },
	{ {  1.0, -1.0, -1.0 }, { 1.0, 0.0 } },
	{ {  1.0, -1.0,  1.0 }, { 1.0, 1.0 } },
	{ { -1.0, -1.0,  1.0 }, { 0.0, 1.0 } },
}

TEXTURED_INDICES := [?]u16 {
	// Front
	0, 1, 2,
	2, 3, 0,

	// Back
	4, 5, 6,
	6, 7, 4,

	// Left
	8, 9, 10,
	10, 11, 8,

	// Right
	12, 13, 14,
	14, 15, 12,

	// Top
	16, 17, 18,
	18, 19, 16,

	// Bottom
	20, 21, 22,
	22, 23, 20,
}

Arguments :: struct #packed {
	model:		matrix[4,4]f32,
	view:		matrix[4,4]f32,
	proj:		matrix[4,4]f32,

	vertices:	uintptr,
}

Textured_Arguments :: struct #packed {
	model:		matrix[4,4]f32,
	view:		matrix[4,4]f32,
	proj:		matrix[4,4]f32,

	vertices:	uintptr,
	texture:	u32,
	sampler:	u32,
}

Blit_Arguments :: struct #packed {
	texture:	u32,
	sampler:	u32,
	flip_y:		b32,
}

device_info:		gfx.Device_Info

surface:		gfx.Surface
surface_format:		gfx.Pixel_Format

default_memory:		gfx.Arena
private_memory:		gfx.Arena
framebuffers_memory:	gfx.Arena
staging_memory:		gfx.Scratch
frame_memory:		gfx.Scratch

color_vertices:		[]Color_Vertex
gpu_color_vertices:	uintptr
indices:		[]u16
textured_vertices:	[]Textured_Vertex
gpu_textured_vertices:	uintptr
textured_indices:	[]u16

color_buffer:		gfx.Texture
color_buffer_view:	gfx.View
depth_buffer:		gfx.Texture
depth_buffer_view:	gfx.View
depth_format:		gfx.Pixel_Format

depth_stencil:		gfx.Depth_Stencil_State
depth_disabled_stencil:	gfx.Depth_Stencil_State

grass_texture:		gfx.Texture
grass_view:		gfx.View
linear_sampler:		gfx.Sampler
nearest_sampler:	gfx.Sampler

resource_set:		gfx.Resource_Set

blend_state:		gfx.Blend_State
ui_blit_blend_state:	gfx.Blend_State
pipeline:		gfx.Pipeline
blend_pipeline:		gfx.Pipeline
textured_pipeline:	gfx.Pipeline
blit_pipeline:		gfx.Pipeline

frame_semaphore:	gfx.Semaphore
frame_count:		int

camera:			Camera
cube_rotation:		f32

setup :: proc() {
	ensure(sdl.Init({ .VIDEO }) == true)

	window_flags := sdl.WindowFlags { .RESIZABLE, .HIGH_PIXEL_DENSITY }
	// window_flags := sdl.WindowFlags { .RESIZABLE }
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

	pixel_w, pixel_h: i32
	sdl.GetWindowSizeInPixels(window, &pixel_w, &pixel_h)
	window_state.dimensions = { cast(int)pixel_w, cast(int)pixel_h }

	gfx.init()

	devices, _ := gfx.enumerate_devices()
	log.infof("%#v", devices)

	device := devices[0].id
	when gfx.TARGET_API == .Vulkan {
		for device_info in devices {
			// NOTE: MoltenVK has issues with the deallocation of resources from multiple threads.
			//	Prefer using KosmicKrisp since it does not have this problem.
			if device_info.driver == "KosmicKrisp" {
				device = device_info.id
				break
			}
		}
	}
	log.debugf("Testing using device with Device_ID %d (%s - %s).", device, devices[device].name, devices[device].driver)

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
		if gfx._device_info.properties.transfer_queue {
			gfx.wait_idle(.Transfer)
		}
		gfx.destroy_texture(depth_buffer)
	}
	gfx.arena_free_all(&framebuffers_memory)

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
	color_buffer_memory := gfx.arena_alloc(&framebuffers_memory, color_buffer_size, color_buffer_align) or_return
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
	depth_buffer_memory := gfx.arena_alloc(&framebuffers_memory, depth_buffer_size, depth_buffer_align) or_return
	depth_buffer = gfx.create_texture(depth_buffer_memory, depth_buffer_descriptor) or_return
	depth_buffer_view = gfx.default_view_of(depth_buffer) or_return
	depth_format = .D32_Float

	camera.fov	= la.to_radians(cast(f32)95.0)
	camera.aspect	= cast(f32)window_state.dimensions.x / cast(f32)window_state.dimensions.y
	camera.near	= 0.01
	camera.far	= 100.0

	ui_resize_screen(window_state.scaled_dimensions, window_state.dimensions) or_return

	return nil
}

skybox_vertices:	[][3]f32
skybox_indices:		[]u16
gpu_skybox_vertices:	uintptr

skybox_texture:		gfx.Texture
skybox_view:		gfx.View

skybox_pipeline:	gfx.Pipeline

transfer_queue :: proc() -> gfx.Queue {
	if device_info.properties.transfer_queue {
		return .Transfer
	} else {
		return .Default
	}
}

setup_skybox :: proc(image_paths: [6]string, synchronization := gfx.Synchronization_Group{}) -> gfx.Result {
	SKYBOX_VERTICES := [?][3]f32 {
		{ -1.0, -1.0, -1.0 },
		{  1.0, -1.0, -1.0 },
		{  1.0,  1.0, -1.0 },
		{ -1.0,  1.0, -1.0 },

		{ -1.0, -1.0,  1.0 },
		{  1.0, -1.0,  1.0 },
		{  1.0,  1.0,  1.0 },
		{ -1.0,  1.0,  1.0 },
	}
	Pixel :: [4]u8

	images: [6][^]byte
	dimensions: [3]int

	for path, i in image_paths {

		x, y, c: i32
		images[i] = image.load(strings.clone_to_cstring(path, context.temp_allocator), &x, &y, &c, 4)

		dimensions.x	= cast(int)x
		dimensions.y	= cast(int)y
		dimensions.z	= 1
	}

	skybox_texture_descriptor := gfx.Texture_Descriptor {
		type		= .D2_Array,
		dimensions	= dimensions,
		layer_count	= 6,
		format		= .RGBA8_Unorm,
		usage		= { .Sampled },
	}
	skybox_texture_size, skybox_texture_align := gfx.size_align_of(skybox_texture_descriptor) or_return
	skybox_texture_memory := gfx.arena_alloc(&private_memory, skybox_texture_size, skybox_texture_align) or_return
	skybox_texture = gfx.create_texture(skybox_texture_memory, skybox_texture_descriptor) or_return

	skybox_view_descriptor := gfx.View_Descriptor {
		type		= .Cube,
		layer_count	= 6,
	}
	skybox_view = gfx.create_view(skybox_texture, skybox_view_descriptor) or_return

	skybox_vertices = gfx.arena_alloc(&default_memory, [][3]f32, len(SKYBOX_VERTICES)) or_return
	gpu_skybox_vertices = gfx.gpu_address_of(raw_data(skybox_vertices)) or_return
	copy(skybox_vertices, SKYBOX_VERTICES[:])

	skybox_indices = gfx.arena_alloc(&default_memory, []u16, len(INDICES)) or_return
	copy(skybox_indices, INDICES[:])

	skybox_bytes, _ := gfx.load_bytecode_of("skybox", "build", context.temp_allocator)
	skybox_pipeline_descriptor := gfx.Render_Pipeline_Descriptor {
		vertex_stage	= {
			bytecode	= skybox_bytes,
			entrypoint	= "vertex_main",
		},
		fragment_stage	= {
			bytecode	= skybox_bytes,
			entrypoint	= "fragment_main",
		},
		topology	= .Triangle_List,
		sample_count	= 4,
		color_formats	= { surface_format },
		depth_format	= depth_format,
	}
	skybox_pipeline = gfx.create_render_pipeline(skybox_pipeline_descriptor) or_return

	command_buffer := gfx.begin_command_encoding(transfer_queue()) or_return

	upload_buffer := gfx.scratch_alloc(&staging_memory, []Pixel, dimensions.x * dimensions.y * 6) or_return
	for img, i in images {
		size := dimensions.x * dimensions.y
		offset := dimensions.x * dimensions.y * i

		current_upload_buffer := upload_buffer[offset:offset+size]
		copy(slice.to_bytes(current_upload_buffer), slice.bytes_from_ptr(img, size * size_of(Pixel)))

		region := gfx.Texture_Region {
			base_layer	= i,
			layer_count	= 1,
			size		= dimensions,
		}
		gfx.copy_buffer_to_texture(
			command_buffer,
			raw_data(current_upload_buffer),
			skybox_texture,
			region,
		) or_return

		image.image_free(img)
	}

	gfx.synchronize(command_buffer, synchronization)
	gfx.submit(transfer_queue(), command_buffer)

	return nil
}

draw_skybox :: proc(
	command_buffer: gfx.Command_Buffer,
	camera_view:		matrix[4,4]f32,
	camera_proj:		matrix[4,4]f32,
	skybox_view_index:	int,
	sampler_index:	int,
) -> gfx.Result {

	Draw_Skybox_Arguments :: struct #packed {
		view:			matrix[4,4]f32,
		proj:			matrix[4,4]f32,

		vertices:		uintptr,
		skybox_view_index:	u32,
		sampler_index:		u32,
	}

	arguments := gfx.scratch_alloc(&frame_memory, Draw_Skybox_Arguments) or_return
	arguments^ = {
		view			= la.to_matrix4(la.to_matrix3(camera_view)),
		proj			= camera_proj,
		vertices		= gpu_skybox_vertices,
		skybox_view_index	= cast(u32)skybox_view_index,
		sampler_index		= cast(u32)sampler_index,
	}

	gfx.draw_indexed(command_buffer, skybox_pipeline, arguments, raw_data(skybox_indices), 36) or_return

	return nil
}

create_texture :: proc(path: string, synchronization := gfx.Synchronization_Group{}) -> (texture: gfx.Texture, view: gfx.View, res: gfx.Result) {
	channels_to_format := [?]gfx.Pixel_Format {
		0	= .None,
		1	= .R8_Unorm,
		2	= .RG8_Unorm,
		3	= .None,
		4	= .RGBA8_Unorm,
	}

	width, height, channels: i32
	pixels := image.load(strings.clone_to_cstring(path, context.temp_allocator), &width, &height, &channels, 0)

	dimensions := [3]int{
		cast(int)width, cast(int)height, 1,
	}
	texture_descriptor := gfx.Texture_Descriptor {
		type		= .D2_Array,
		dimensions	= dimensions,
		mip_count	= 4,
		format		= channels_to_format[channels],
		usage		= { .Sampled },
	}
	texture_size, texture_align := gfx.size_align_of(texture_descriptor) or_return
	texture_memory := gfx.arena_alloc(&private_memory, texture_size, texture_align) or_return
	texture = gfx.create_texture(texture_memory, texture_descriptor) or_return
	defer if res != nil do gfx.destroy_texture(texture)
	view = gfx.default_view_of(texture) or_return

	upload_buffer := gfx.scratch_alloc(&frame_memory, width * height * channels) or_return
	mem.copy(upload_buffer, pixels, cast(int)(width * height * channels))

	command_buffer := gfx.begin_command_encoding(transfer_queue()) or_return
		texture_region := gfx.Texture_Region {
			size		= dimensions,
			layer_count	= 1,
		}
		gfx.copy_buffer_to_texture(
			command_buffer,
			upload_buffer,
			texture,
			texture_region,
		) or_return
		gfx.barrier(command_buffer, { .Transfer }, { .Transfer }) or_return
		gfx.generate_mipmaps_for(command_buffer, texture) or_return
	gfx.synchronize(command_buffer, synchronization) or_return
	gfx.submit(transfer_queue(), command_buffer) or_return

	return
}

app :: proc() -> Result {

	frame_semaphore = gfx.create_semaphore(.Cpu) or_return

	gfx.create_arena	(&default_memory,	.Default, 256	* mem.Megabyte) or_return
	gfx.create_arena	(&framebuffers_memory,	.Private, 512	* mem.Megabyte) or_return
	gfx.create_arena	(&private_memory,	.Private, 256	* mem.Megabyte) or_return
	gfx.create_scratch	(&staging_memory,	.Staging, 32	* mem.Megabyte) or_return
	gfx.create_scratch	(&frame_memory,		.Default, 32	* mem.Megabyte) or_return

	tl_track_memory("default_memory", &default_memory)
	tl_track_memory("private_memory", &private_memory)
	tl_track_memory("staging_memory", &staging_memory)
	tl_track_memory("framebuffers_memory", &framebuffers_memory)
	tl_track_memory("frame_memory", &frame_memory)
	tl_track_internal_gfx_memory()

	rd_init_resource_manager(rd_resource_manager()) or_return

	tx_init(&private_memory, &default_memory, context.allocator)
	defer tx_fini()

	ui_init(window_state.dimensions, &framebuffers_memory, &frame_memory, context.allocator) or_return

	// tx_register_font_root("./res/fonts/IBMPlexSans.ttf")
	tx_register_font_root("./res/fonts/NotoSans-Regular.ttf")
	tx_register_font("./res/fonts/NotoSansSymbols2-Regular.ttf", 20) or_return
	// font3 := tx_register_font("./res/fonts/NotoSansJP.ttf", 50) or_return
	// font4 := tx_register_font("./res/fonts/NotoSansJP.ttf", 20) or_return
	// glyph_iter := tx_make_glyph_iterator(font3, "Hello friends!", {}) or_return
	// font_view: gfx.View
	// for draw_info in tx_iterate_glyph(&glyph_iter) {
	// 	font_view = draw_info.atlas_view
	// }

	// ui_ctx := ui_setup(
	// 	transfer_queue(),
	// 	&default_memory,
	// 	&private_memory,
	// 	&frame_memory,
	// 	&framebuffers_memory,
	// 	window_state.dimensions,
	// ) or_return

	color_vertices = gfx.arena_alloc(&default_memory, []Color_Vertex, len(COLOR_VERTICES)) or_return
	copy(color_vertices, COLOR_VERTICES[:])
	gpu_color_vertices = gfx.gpu_address_of(raw_data(color_vertices)) or_return

	indices = gfx.arena_alloc(&default_memory, []u16, len(INDICES)) or_return
	copy(indices, INDICES[:])

	textured_vertices = gfx.arena_alloc(&default_memory, []Textured_Vertex, len(TEXTURED_VERTICES)) or_return
	copy(textured_vertices, TEXTURED_VERTICES[:])
	gpu_textured_vertices = gfx.gpu_address_of(raw_data(textured_vertices)) or_return

	textured_indices = gfx.arena_alloc(&default_memory, []u16, len(TEXTURED_INDICES)) or_return
	copy(textured_indices, TEXTURED_INDICES[:])

	prepare_stuff_for_window_size()

	depth_stencil = gfx.create_depth_stencil_state(gfx.Depth_Stencil_Descriptor {
		depth_enable	= true,
		depth_write	= true,
		depth_test	= .Less_Equal,
	}) or_return
	depth_disabled_stencil = gfx.create_depth_stencil_state(gfx.Depth_Stencil_Descriptor {
		depth_enable	= false,
	}) or_return

	linear_sampler = gfx.create_sampler(gfx.Sampler_Descriptor {
		min_filter	= .Linear,
		mag_filter	= .Linear,
		mip_filter	= .Linear,
		max_anisotropy	= 8,
	}) or_return
	nearest_sampler = gfx.create_sampler(gfx.Sampler_Descriptor {
		min_filter	= .Linear,
		mag_filter	= .Nearest,
		mip_filter	= .Linear,
		max_anisotropy	= 8,
	}) or_return

	resource_set = gfx.create_resource_set() or_return

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

	blend_descriptor := gfx.Blend_Descriptor {
		color_op			= .Add,
		source_color_factor		= .Source_Alpha,
		destination_color_factor	= .One_Minus_Source_Alpha,
		alpha_op			= .Add,
		source_alpha_factor		= .One,
		destination_alpha_factor	= .One_Minus_Source_Alpha,
	}
	blend_state = gfx.create_blend_state(blend_descriptor) or_return
	ui_blit_blend_state = gfx.create_blend_state(gfx.Blend_Descriptor {
		color_op			= .Add,
		source_color_factor		= .One,
		destination_color_factor	= .One_Minus_Source_Alpha,
		alpha_op			= .Add,
		source_alpha_factor		= .One,
		destination_alpha_factor	= .One_Minus_Source_Alpha,
	}) or_return
	blend_pipeline_descriptor := gfx.Render_Pipeline_Descriptor {
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
		blend_state	= blend_state,
	}
	blend_pipeline = gfx.create_render_pipeline(blend_pipeline_descriptor) or_return

	textured_pipeline_bytecode, _ := gfx.load_bytecode_of("texture_basic", "./build", context.temp_allocator)
	textured_pipeline_descriptor := gfx.Render_Pipeline_Descriptor {
		vertex_stage	= {
			bytecode	= textured_pipeline_bytecode,
			entrypoint	= "vertex_main",
		},
		fragment_stage	= {
			bytecode	= textured_pipeline_bytecode,
			entrypoint	= "fragment_main",
		},
		topology	= .Triangle_List,
		cull		= .Clockwise,
		sample_count	= 4,
		color_formats	= { surface_format },
		depth_format	= depth_format,
		blend_state	= blend_state,
	}
	textured_pipeline = gfx.create_render_pipeline(textured_pipeline_descriptor) or_return

	blit_pipeline_bytecode, _ := gfx.load_bytecode_of("blit", "./build", context.temp_allocator)
	blit_pipeline_descriptor := gfx.Render_Pipeline_Descriptor {
		vertex_stage	= {
			bytecode	= blit_pipeline_bytecode,
			entrypoint	= "vertex_main",
		},
		fragment_stage	= {
			bytecode	= blit_pipeline_bytecode,
			entrypoint	= "fragment_main",
		},
		topology	= .Triangle_List,
		cull		= .None,
		sample_count	= 4,
		color_formats	= { surface_format },
		depth_format	= depth_format,
		blend_state	= ui_blit_blend_state,
	}
	blit_pipeline = gfx.create_render_pipeline(blit_pipeline_descriptor) or_return

	grass_texture, grass_view = create_texture("./res/textures/Grass.png") or_return
	setup_skybox({
		"./res/textures/skybox_positive_x_small.png",
		"./res/textures/skybox_negative_x_small.png",
		"./res/textures/skybox_positive_y_small.png",
		"./res/textures/skybox_negative_y_small.png",
		"./res/textures/skybox_positive_z_small.png",
		"./res/textures/skybox_negative_z_small.png",
	}) or_return

	gfx.wait_idle(transfer_queue())

	// gfx.set_texture_set(resource_set, .D2, { grass_view, ui_frame_buffer_view, font_view }) or_return
	gfx.set_texture_set(resource_set, .D2, { grass_view, grass_view }) or_return
	gfx.set_texture_set(resource_set, .Cube, { skybox_view }) or_return
	gfx.set_sampler_set(resource_set, { linear_sampler, nearest_sampler }) or_return
	// gfx.set_sampler_set(resource_set, { nearest_sampler }) or_return

	prev_time := time.tick_now()
	delta_time: f32

	ui_semaphore := gfx.create_semaphore(.Timeline) or_return

	for !should_quit {
		frame_count += 1
		if frame_count > 3 {
			gfx.wait_semaphore(frame_semaphore, frame_count - 3)
		}
		// gfx.wait_semaphore(frame_semaphore, frame_count - 1)

		process_events()
		tl_begin_frame()

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
		if .Just_Pressed in key_states[.Z] {
			camera.fov	= cast(f32)la.to_radians(45.0)
		} else if .Just_Released in key_states[.Z] {
			camera.fov	= cast(f32)la.to_radians(95.0)
		}
		if .Just_Pressed in key_states[.K] {
			ui_toggle_debug_mode()
		}
		move_camera(&camera, input, speed, delta_time)

		if mouse_state.captured || .Pressed in mouse_state.buttons[.Right] {
			camera_rotation := mouse_state.delta / 500.0
			camera_rotation.x, camera_rotation.y = camera_rotation.y, camera_rotation.x
			camera_rotation.x *= -1
			rotate_camera(&camera, camera_rotation)
		}

		view, proj := get_camera_matrices(camera)

		// ui_tick()
		// ui.begin(ui_ctx)
		// ui_memory_tracker(ui_ctx)
		// ui.end(ui_ctx)

		surface_view:		gfx.View
		surface_semaphore:	gfx.Semaphore
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
					view		= color_buffer_view,
					resolve_view	= surface_view,
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

		rd_cycle_resource_manager(rd_resource_manager())
		rd_apply_resource_manager_updates(rd_resource_manager())

		do_ui(delta_time, {
			wait	= {
				{ surface_semaphore, 0, { .Color_Attachment } },
			},
			signal	= {
				{ ui_semaphore, frame_count, { .Color_Attachment } },
			},
		}) or_return

		command_buffer := gfx.begin_command_encoding(.Default) or_return

		tx_sync_font_textures(command_buffer) or_return

		gfx.begin_render_pass(command_buffer, render_pass_descriptor)
			gfx.use_resources(command_buffer, resource_set)

			gfx.use_depth_stencil_state(command_buffer, depth_stencil) or_return
			args := gfx.scratch_alloc(&frame_memory, Arguments, 16) or_return
			args^ = {
				vertices	= gpu_color_vertices,
				model		= la.matrix4_translate_f32({ 0.0, 0.0, -5.0}) * la.matrix4_rotate_f32(cube_rotation, { 0.0, 1.0, 0.0 }),
				view		= view,
				proj		= proj,
			}
			gfx.draw_indexed(command_buffer, pipeline, args, raw_data(indices), 36) or_return

			tex_args := gfx.scratch_alloc(&frame_memory, Textured_Arguments, 16) or_return
			tex_args^ = {
				vertices	= gpu_textured_vertices,
				model		= la.matrix4_translate_f32({ 5.0, 0.0, -5.0}) * la.matrix4_rotate_f32(cube_rotation, { 0.0, 1.0, 0.0 }),
				view		= view,
				proj		= proj,
				texture		= 0,
				sampler		= 1,
			}
			gfx.draw_indexed(command_buffer, textured_pipeline, tex_args, raw_data(textured_indices), 36) or_return

			args = gfx.scratch_alloc(&frame_memory, Arguments, 16) or_return
			args^ = {
				vertices	= gpu_color_vertices,
				model		= la.matrix4_translate_f32({ 0.0, 0.0, -10.0}) * la.matrix4_scale_f32(15.0),
				view		= view,
				proj		= proj,
			}
			gfx.draw_indexed(command_buffer, blend_pipeline, args, raw_data(indices), 6) or_return

			tex_args = gfx.scratch_alloc(&frame_memory, Textured_Arguments, 16) or_return
			tex_args^ = {
				vertices	= gpu_textured_vertices,
				model		= la.matrix4_translate_f32({ 0.0, 0.0, -5.0}) * la.matrix4_scale_f32(2.0),
				view		= view,
				proj		= proj,
				texture		= 1,
				sampler		= 0,
			}
			gfx.draw_indexed(command_buffer, textured_pipeline, tex_args, raw_data(textured_indices), 6) or_return
			draw_skybox(command_buffer, view, proj, 0, 0) or_return

			gfx.use_depth_stencil_state(command_buffer, depth_disabled_stencil)
			gfx.use_resources(command_buffer, rd_current_resource_set_of(rd_resource_manager()))
			blit_args := gfx.scratch_alloc(&frame_memory, Blit_Arguments) or_return
			blit_args^ = {
				texture	= cast(u32)_ui.resolve_frame_buffer_resource_id,
				sampler	= cast(u32)_ui.sampler_resource_id,
				flip_y	= true,
			}
			gfx.draw(command_buffer, blit_pipeline, blit_args, 3) or_return
		gfx.end_render_pass(command_buffer) or_return

		gfx.synchronize(command_buffer, {
			wait = {
				{ ui_semaphore, frame_count, { .Transfer } },
			},
			signal = {
				{ frame_semaphore, frame_count, { .Color_Attachment } },
			},
		})
		gfx.submit(.Default, command_buffer) or_return
		gfx.present(.Default, surface_view, { frame_semaphore, frame_count }) or_return

		tl_end_frame()
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

	tl_init_memtrack()
	defer tl_fini_memtrack()

	res := app()
	if res != nil do log.fatalf("Example failed with error %v.", res)
}

do_ui :: proc(delta_time: f32, synchronization: gfx.Synchronization_Group) -> Result {
	if ui.UI(ui.ID("Stats_Widget"))({
		layout	= {
			sizing = {
				ui.SizingFit({ min = 100.0 }),
				ui.SizingFit({}),
			},
			padding	= ui.PaddingAll(5),
			childAlignment	= {
				x	= .Left,
				y	= .Top,
			},
			layoutDirection	= .TopToBottom,
			childGap	= 5,
		},
		cornerRadius	= {
			0, 0, 0, 10,
		},
		backgroundColor	= { **ui.PRIMARY_900.rgb, 90 },
		floating = {
			zIndex		= 256,
			attachTo	= .Root,
			attachment	= {
				element	= .LeftTop,
				parent	= .LeftTop,
			},
			pointerCaptureMode = .Passthrough,
		},
	}) {
		ui.Text(gfx.TARGET_API_STRING, {
			textColor	= { 25, 255, 25, 255 } when gfx.TARGET_API == .Metal_3 else { 255, 25, 25, 255 },
			fontSize	= 20,
		})

		if ui.UI(ui.ID_LOCAL("Grid"))({
			layout	= {
				sizing = {
					ui.SizingGrow({}),
					ui.SizingGrow({}),
				},
				layoutDirection	= .LeftToRight,
			},
		}) {
			if ui.UI(ui.ID_LOCAL("Labels"))({
				layout	= {
					sizing = {
						ui.SizingPercent(0.30),
						ui.SizingGrow({}),
					},
					layoutDirection	= .TopToBottom,
				},
			}) {
				ui.Text("FPS:", {
					textColor	= { 255, 255, 255, 255 },
					fontSize	= 20,
				})
				ui.Text("MS:", {
					textColor	= { 255, 255, 255, 255 },
					fontSize	= 20,
				})
			
			}
			if ui.UI(ui.ID_LOCAL("Stats"))({
				layout	= {
					sizing = {
						ui.SizingGrow({}),
						ui.SizingGrow({}),
					},
					layoutDirection	= .TopToBottom,
					childAlignment	= {
						.Right,
						.Top,
					},
				},
			}) {
				ui.TextDynamic(fmt.tprintf("%.2f", 1.0/delta_time), {
					textColor	= { 255, 255, 255, 255 },
					fontSize	= 20,
				})
				ui.TextDynamic(fmt.tprintf("%.2f", delta_time * 1000.0), {
					textColor	= { 255, 255, 255, 255 },
					fontSize	= 20,
				})
			}
		}
	}

	if ui.UI(ui.ID("Demo_Widget"))({
		layout		= {
			sizing	= {
				width	= ui.SizingFit({}),
				height	= ui.SizingFit({}),
			},
			padding = { 3, 3, 0, 1 },
		},
		backgroundColor	= { **ui.PRIMARY_900.rgb, 90 },
		cornerRadius	= { 0.0, 5.0, 0.0, 0.0 },
		floating	= {
			zIndex		= 256,
			attachment	= {
				element	= .LeftBottom,
				parent	= .LeftBottom,
			},
			pointerCaptureMode = .Passthrough,
			attachTo	= .Root,
		},
	}) {
		ui.Text("vicixdev_gfx demo", {
			wrapMode	= .Newlines,
			textColor	= { 255, 255, 255, 255 },
			fontSize	= 20,
		})
	}

	@static
	memory_window := ui_Window_Persistent_Data {
		position	= 300,
		dimensions	= 300,
	}
	window_config := ui_Window_Config {
		persistent	= &memory_window,
		title		= "Memory Tracker",
	}
	if .Just_Pressed in key_states[.M] {
		memory_window.status	= .Normal
	}
	if ui_Window(ui.ID("Window"), &window_config) {
		tl_Memory_Tracker()
	}

	ui_render(synchronization) or_return

	return nil
}

