package main

import ui "vendor:microui"
import "gfx"

ui_Vertex :: struct #packed {
	position:	[2]f32,
	uv:		[2]f32,
}

/*
out color = color * color_factor + sample(texture, uv) * (1 - color_factor)
*/
ui_Quad :: struct {
	vertices:		[4]ui_Vertex,
	color:			[4]f32,
	texture:		u32,
	color_factor:		f32,
}

ui_Render_Arguments :: struct #packed {
	// [^]ui_Quad
	quads:			uintptr,
	screen_dimensions:	[2]f32,
}

@(rodata)
ui_QUAD_INDICES := [?]u16 {
	0, 1, 2,
	2, 3, 0,
}

ui_context:		ui.Context

ui_private_memory:	^gfx.Arena
ui_default_memory:	^gfx.Arena
ui_frame_memory:	^gfx.Scratch
ui_frame_buffer_memory:	^gfx.Arena

ui_blend_state:		gfx.Blend_State
ui_pipeline:		gfx.Pipeline

ui_indices:		[]u16
ui_atlas_texture:	gfx.Texture
ui_atlas_view:		gfx.View
ui_frame_buffer:	gfx.Texture
ui_frame_buffer_view:	gfx.View
ui_sampler:		gfx.Sampler
ui_resource_set:	gfx.Resource_Set

ui_screen_dimensions:	[3]int

ui_setup :: proc(
	transfer_queue:		gfx.Queue,
	default_memory:		^gfx.Arena,
	private_memory:		^gfx.Arena,
	frame_memory:		^gfx.Scratch,
	frame_buffer_memory:	^gfx.Arena,
	screen_size:		[2]int,
	on_done:		..gfx.Semaphore_Signal,
) -> (ctx: ^ui.Context, res: gfx.Result) {

	ui_default_memory	= default_memory
	ui_private_memory	= private_memory
	ui_frame_memory		= frame_memory
	ui_frame_buffer_memory	= frame_buffer_memory

	// Indices setup
	ui_indices = gfx.arena_alloc(ui_default_memory, []u16, len(ui_QUAD_INDICES)) or_return
	copy(ui_indices, ui_QUAD_INDICES[:])

	// Sampler setup
	sampler_descriptor := gfx.Sampler_Descriptor {
		min_filter	= .Nearest,
		mag_filter	= .Nearest,
		mip_filter	= .Linear,
		address_u	= .Mirrored_Repeat,
		address_v	= .Mirrored_Repeat,
		address_w	= .Clamp_To_Edge,
	}
	ui_sampler = gfx.create_sampler(sampler_descriptor) or_return

	// Blend state
	blend_descriptor := gfx.Blend_Descriptor {
		color_op			= .Add,
		source_color_factor		= .Source_Alpha,
		destination_color_factor	= .One_Minus_Source_Alpha,
		alpha_op			= .Add,
		source_alpha_factor		= .One,
		destination_alpha_factor	= .One_Minus_Source_Alpha,
	}
	ui_blend_state = gfx.create_blend_state(blend_descriptor) or_return

	// Pipeline setup
	pipeline_bytecode, bytecode_res := gfx.load_bytecode_of("ui_render", "./build", context.temp_allocator)
	assert(bytecode_res == nil, "Could not load the microui renderer pipeline bytecode.")
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
		// sample_count	= 4,
		sample_count	= 1,
		color_formats	= { .RGBA8_Unorm },
		blend_state	= ui_blend_state,
	}
	ui_pipeline = gfx.create_render_pipeline(pipeline_descriptor) or_return

	// Frame buffer setup
	ui_resize_screen(screen_size) or_return

	// Atlas setup
	dimensions := [3]int{
		ui.DEFAULT_ATLAS_WIDTH, ui.DEFAULT_ATLAS_HEIGHT, 1,
	}
	atlas_texture_descriptor := gfx.Texture_Descriptor {
		type		= .D2_Array,
		dimensions	= dimensions,
		format		= .R8_Unorm,
		usage		= { .Sampled },
	}
	atlas_size, atlas_align := gfx.size_align_of(atlas_texture_descriptor) or_return
	atlas_memory := gfx.arena_alloc(ui_private_memory, atlas_size, atlas_align) or_return
	ui_atlas_texture = gfx.create_texture(atlas_memory, atlas_texture_descriptor) or_return
	ui_atlas_view = gfx.default_view_of(ui_atlas_texture) or_return

	upload_buffer := gfx.scratch_alloc(ui_frame_memory, []byte, len(ui.default_atlas_alpha)) or_return
	copy(upload_buffer, ui.default_atlas_alpha[:])

	command_buffer := gfx.begin_command_encoding(transfer_queue) or_return
		region := gfx.Texture_Region {
			size		= dimensions,
			layer_count	= 1,
		}
		gfx.copy_buffer_to_texture(command_buffer, raw_data(upload_buffer), ui_atlas_texture, region) or_return
	gfx.submit(transfer_queue, { command_buffer }, ..on_done) or_return

	// Resource set setup
	ui_resource_set = gfx.create_resource_set() or_return
	gfx.set_texture_set(ui_resource_set, .D2, { ui_atlas_view }) or_return
	gfx.set_sampler_set(ui_resource_set, { ui_sampler }) or_return

	// Context setup
	ui_init_context(&ui_context)

	return &ui_context, nil
}

ui_resize_screen :: proc(screen_size: [2]int) -> (res: gfx.Result) {
	if ui_frame_buffer != {} {
		gfx.destroy_texture(ui_frame_buffer)
	}

	ui_screen_dimensions = { **screen_size, 1 }
	frame_buffer_descriptor := gfx.Texture_Descriptor {
		type		= .D2_Array,
		dimensions	= ui_screen_dimensions,
		format		= .RGBA8_Unorm,
		// sample_count	= 4,
		usage		= { .Color_Attachment, .Sampled },
	}
	frame_buffer_size, frame_buffer_align := gfx.size_align_of(frame_buffer_descriptor) or_return
	frame_buffer_memory := gfx.arena_alloc(ui_frame_buffer_memory, frame_buffer_size, frame_buffer_align) or_return
	ui_frame_buffer = gfx.create_texture(frame_buffer_memory, frame_buffer_descriptor) or_return
	ui_frame_buffer_view = gfx.default_view_of(ui_frame_buffer) or_return

	return nil
}

ui_init_context :: proc(ctx: ^ui.Context) {
	set_clipboard :: proc(user_data: rawptr, text: string) -> (ok: bool) {
		return true
	}
	get_clipboard :: proc(user_data: rawptr) -> (text: string, ok: bool) {
		return "", true
	}

	ui.init(ctx, set_clipboard, get_clipboard, nil)
	ctx.text_width	= ui.default_atlas_text_width
	ctx.text_height	= ui.default_atlas_text_height
}

ui_tick :: proc() {

	@(static, rodata)
	MOUSE_BUTTON_TO_UI_MOUSE := #partial[Mouse_Button]ui.Mouse {
		.Left		= .LEFT,
		.Right		= .RIGHT,
		.Middle		= .MIDDLE,
	}

	ui.input_mouse_move(&ui_context, cast(i32)mouse_state.position.x, cast(i32)mouse_state.position.y)

	for state, button in mouse_state.buttons {
		if button < .Left || button > .Middle {
			continue
		}

		if .Just_Pressed in state {
			ui.input_mouse_down(
				&ui_context,
				cast(i32)(mouse_state.position.x),
				cast(i32)(mouse_state.position.y),
				MOUSE_BUTTON_TO_UI_MOUSE[button],
			)
		}
		if .Just_Released in state {
			ui.input_mouse_up(
				&ui_context,
				cast(i32)(mouse_state.position.x),
				cast(i32)(mouse_state.position.y),
				MOUSE_BUTTON_TO_UI_MOUSE[button],
			)
		}
	}
}

ui_render :: proc(command_buffer: gfx.Command_Buffer) -> gfx.Result {

	backing: ^ui.Command
	quad_count := 0
	for variant in ui.next_command_iterator(&ui_context, &backing) {
		switch command in variant {
		case ^ui.Command_Rect:
			quad_count += 1
		case ^ui.Command_Icon:
			quad_count += 1
		case ^ui.Command_Text:
			quad_count += len(command.str)
		case ^ui.Command_Clip:
		case ^ui.Command_Jump:
		}
	}

	quads := gfx.scratch_alloc(ui_frame_memory, []ui_Quad, quad_count) or_return
	issued_quads := 0

	current_clip := ui.Rect { 0, 0, cast(i32)ui_screen_dimensions.x, cast(i32)ui_screen_dimensions.y }

	backing = nil
	for variant in ui.next_command_iterator(&ui_context, &backing) {
		switch command in variant {
		case ^ui.Command_Rect:

			should_cull := construct_quad(
				&quads[issued_quads],
				command.rect,
				{},
				command.color,
				1.0,
				0,
				current_clip,
			)
			if should_cull {
				continue
			}

			issued_quads += 1

		case ^ui.Command_Clip:

			current_clip = command.rect

		case ^ui.Command_Icon:

			icon_rect := ui.default_atlas[command.id]

			should_cull := construct_quad(
				&quads[issued_quads],
				command.rect,
				icon_rect,
				command.color,
				0.0,
				0,
				current_clip,
			)
			if should_cull {
				continue
			}

			issued_quads += 1

		case ^ui.Command_Text:
			position := command.pos
			for character in command.str {
				if character & 0xc0 == 0x80 {
					continue
				}

				icon_rect := ui.default_atlas[ui.DEFAULT_ATLAS_FONT + int(character)]

				should_cull := construct_quad(
					&quads[issued_quads],
					ui.Rect{
						**position, icon_rect.w, icon_rect.h,
					},
					icon_rect,
					command.color,
					0.0,
					0,
					current_clip,
				)
				if should_cull {
					continue
				}

				issued_quads += 1
				position.x += icon_rect.w
			}

		case ^ui.Command_Jump:
			unreachable()
		}
	}

	draw_arguments := gfx.scratch_alloc(ui_frame_memory, ui_Render_Arguments) or_return
	draw_arguments^ = {
		quads	= gfx.gpu_address_of(raw_data(quads)) or_return,
		screen_dimensions	= {
			cast(f32)ui_screen_dimensions.x, cast(f32)ui_screen_dimensions.y,
		},
	}

	render_pass_descriptor := gfx.Render_Pass_Descriptor {
		color_attachments	= {
			gfx.Render_Attachment {
				view		= ui_frame_buffer_view,
				load_operation	= .Clear,
				store_operation	= .Store,
				clear_value	= [4]f64{ 0.0, 0.0, 0.0, 0.2 },
			},
		},
	}
	gfx.begin_render_pass(command_buffer, render_pass_descriptor) or_return
		gfx.use_resources(command_buffer, ui_resource_set) or_return
		gfx.draw_indexed(command_buffer, ui_pipeline, draw_arguments, raw_data(ui_indices), 6, issued_quads) or_return
	gfx.end_render_pass(command_buffer) or_return

	return nil
}

ui_clip_vertices :: proc(clip: ui.Rect, vertices: ^[4]ui_Vertex) -> (should_cull: bool) {
	min_x := cast(f32)clip.x
	min_y := cast(f32)clip.y
	max_x := min_x + cast(f32)clip.w
	max_y := min_y + cast(f32)clip.h

	quad_min_x := vertices[0].position.x
	quad_max_x := vertices[1].position.x
	quad_min_y := vertices[0].position.y
	quad_max_y := vertices[3].position.y

	if quad_max_x <= min_x || quad_min_x >= max_x || quad_max_y <= min_y || quad_min_y >= max_y {
		return true
	}

	uv0 := vertices[0].uv
	uv1 := vertices[1].uv
	uv2 := vertices[2].uv
	uv3 := vertices[3].uv

	if quad_min_x < min_x {
		t := (min_x - quad_min_x) / (quad_max_x - quad_min_x)
		vertices[0].position.x = min_x
		vertices[3].position.x = min_x
		vertices[0].uv.x = uv0.x + (uv1.x - uv0.x) * t
		vertices[3].uv.x = uv3.x + (uv2.x - uv3.x) * t
	}

	if quad_max_x > max_x {
		t := (max_x - quad_min_x) / (quad_max_x - quad_min_x)
		vertices[1].position.x = max_x
		vertices[2].position.x = max_x
		vertices[1].uv.x = uv0.x + (uv1.x - uv0.x) * t
		vertices[2].uv.x = uv3.x + (uv2.x - uv3.x) * t
	}

	if quad_min_y < min_y {
		t := (min_y - quad_min_y) / (quad_max_y - quad_min_y)
		vertices[0].position.y = min_y
		vertices[1].position.y = min_y
		vertices[0].uv.y = uv0.y + (uv3.y - uv0.y) * t
		vertices[1].uv.y = uv1.y + (uv2.y - uv1.y) * t
	}

	if quad_max_y > max_y {
		t := (max_y - quad_min_y) / (quad_max_y - quad_min_y)
		vertices[2].position.y = max_y
		vertices[3].position.y = max_y
		vertices[2].uv.y = uv1.y + (uv2.y - uv1.y) * t
		vertices[3].uv.y = uv0.y + (uv3.y - uv0.y) * t
	}

	return false
}

construct_quad :: proc(
	target:		^ui_Quad,
	quad_rect:	ui.Rect,
	icon_rect:	ui.Rect,
	color:		ui.Color,
	color_factor:	f32,
	texture:	u32,
	current_clip:	ui.Rect,
) -> (culled: bool) {

	target.vertices = [4]ui_Vertex {
		{
			position	= {
				cast(f32)quad_rect.x,
				cast(f32)quad_rect.y,
			},
			uv		= {
				cast(f32)(icon_rect.x) / ui.DEFAULT_ATLAS_WIDTH,
				cast(f32)(icon_rect.y) / ui.DEFAULT_ATLAS_HEIGHT,
			},
		},
		{
			position	= {
				cast(f32)quad_rect.x + cast(f32)quad_rect.w,
				cast(f32)quad_rect.y,
			},
			uv		= {
				cast(f32)(icon_rect.x + icon_rect.w) / ui.DEFAULT_ATLAS_WIDTH,
				cast(f32)(icon_rect.y) / ui.DEFAULT_ATLAS_HEIGHT,
			},
		},
		{
			position	= {
				cast(f32)quad_rect.x + cast(f32)quad_rect.w,
				cast(f32)quad_rect.y + cast(f32)quad_rect.h,
			},
			uv		= {
				cast(f32)(icon_rect.x + icon_rect.w) / ui.DEFAULT_ATLAS_WIDTH,
				cast(f32)(icon_rect.y + icon_rect.h) / ui.DEFAULT_ATLAS_HEIGHT,
			},
		},
		{
			position	= {
				cast(f32)quad_rect.x,
				cast(f32)quad_rect.y + cast(f32)quad_rect.h,
			},
			uv		= {
				cast(f32)(icon_rect.x) / ui.DEFAULT_ATLAS_WIDTH,
				cast(f32)(icon_rect.y + icon_rect.h) / ui.DEFAULT_ATLAS_HEIGHT,
			},
		},
	}

	should_cull := ui_clip_vertices(current_clip, &target.vertices)

	target.texture		= texture
	target.color		= {
		cast(f32)color.r / 255.0,
		cast(f32)color.g / 255.0,
		cast(f32)color.b / 255.0,
		cast(f32)color.a / 255.0,
	}
	target.color_factor	= color_factor

	return should_cull
}

