package main

import "base:runtime"
import "core:log"
import "root:gfx"
import "core:math"
import ui "shared:clay"

_ui_Scissors :: struct {
	position:	[2]int,
	dimensions:	[2]int,
}

_ui: struct {
	error_logger:				runtime.Logger,
	
	allocator:				runtime.Allocator,
	backing_buffer:				[]byte,
	ui_arena:				ui.Arena,
	ui_context:				^ui.Context,
	debug_mode_enabled:			bool,

	frame_buffer_memory:			^gfx.Arena,
	frame_memory:				^gfx.Scratch,

	screen_dimensions:			[2]int,
	scissors:				_ui_Scissors,

	blend_state:				gfx.Blend_State,
	pipeline:				gfx.Pipeline,
	sampler:				gfx.Sampler,
	sampler_resource_id:			int,
	frame_buffer:				gfx.Texture,
	frame_buffer_view:			gfx.View,
	frame_buffer_resource_id:		int,
	resolve_frame_buffer:			gfx.Texture,
	resolve_frame_buffer_view:		gfx.View,
	resolve_frame_buffer_resource_id:	int,
	depth_buffer:				gfx.Texture,
	depth_buffer_view:			gfx.View,
}

ui_init :: proc(
	screen_size:		[2]int,
	frame_buffer_memory:	^gfx.Arena,
	frame_memory:		^gfx.Scratch,
	allocator:		runtime.Allocator,
	logger :=		context.logger,
) -> Result {

	_ui.error_logger	= logger
	_ui.allocator		= allocator
	_ui.screen_dimensions		= screen_size

	required_memory := ui.MinMemorySize()
	_ui.backing_buffer = make([]byte, required_memory, allocator)
	_ui.ui_arena = ui.CreateArenaWithCapacityAndMemory(
		cast(uint)required_memory,
		raw_data(_ui.backing_buffer),
	)

	_ui.ui_context = ui.Initialize(
		_ui.ui_arena,
		ui.Dimensions {
			cast(f32)screen_size.x,
			cast(f32)screen_size.y,
		},
		ui.ErrorHandler {
			_ui_report_error,
			nil,
		},
	)
	ui.SetCurrentContext(_ui.ui_context)
	ui.SetMeasureTextFunction(_ui_measure_text, nil)

	_ui.frame_buffer_memory	= frame_buffer_memory
	_ui.frame_memory	= frame_memory

	sampler_descriptor := gfx.Sampler_Descriptor {
		min_filter	= .Linear,
		mag_filter	= .Linear,
		address_u	= .Clamp_To_Edge,
		address_v	= .Clamp_To_Edge,
		address_w	= .Clamp_To_Edge,
	}
	_ui.sampler = gfx.create_sampler(sampler_descriptor) or_return
	_ui.sampler_resource_id = rd_acquire_sampler_resource_id(rd_resource_manager(), _ui.sampler)

	blend_descriptor := gfx.Blend_Descriptor {
		color_op			= .Add,
		source_color_factor		= .Source_Alpha,
		source_alpha_factor		= .One,
		destination_color_factor	= .One_Minus_Source_Alpha,
		destination_alpha_factor	= .One_Minus_Source_Alpha,
	}
	_ui.blend_state = gfx.create_blend_state(blend_descriptor) or_return

	bytecode := gfx.load_bytecode_of("ui", "build", context.temp_allocator) or_return
	pipeline_descriptor := gfx.Render_Pipeline_Descriptor {
		vertex_stage	= {
			bytecode	= bytecode,
			entrypoint	= "vertex_main",
		},
		fragment_stage	= {
			bytecode	= bytecode,
			entrypoint	= "fragment_main",
		},
		sample_count	= 4,
		topology	= .Triangle_Strip,
		cull		= .None,
		color_formats	= { .RGBA8_Unorm },
		depth_format	= .D32_Float,
		blend_state	= _ui.blend_state,
	}
	_ui.pipeline = gfx.create_render_pipeline(pipeline_descriptor) or_return

	ui_resize_screen(window_state.dimensions) or_return

	ui.BeginLayout()
	return nil
}

ui_toggle_debug_mode :: proc() {
	_ui.debug_mode_enabled = !_ui.debug_mode_enabled
	ui.SetDebugModeEnabled(_ui.debug_mode_enabled)
}

ui_resize_screen :: proc(screen_size: [2]int) -> (res: gfx.Result) {
	if _ui.frame_buffer != {} {
		gfx.destroy_texture(_ui.frame_buffer)
		gfx.destroy_texture(_ui.depth_buffer)
		gfx.destroy_texture(_ui.resolve_frame_buffer)

		rd_release_texture_resource_id(rd_resource_manager(), .D2, _ui.frame_buffer_resource_id)
		rd_release_texture_resource_id(rd_resource_manager(), .D2, _ui.resolve_frame_buffer_resource_id)
	}

	_ui.screen_dimensions = screen_size

	frame_buffer_descriptor := gfx.Texture_Descriptor {
		type		= .D2_Array,
		dimensions	= { **_ui.screen_dimensions, 1 },
		format		= .RGBA8_Unorm,
		sample_count	= 4,
		usage		= { .Color_Attachment, .Sampled },
	}
	frame_buffer_size, frame_buffer_align := gfx.size_align_of(frame_buffer_descriptor) or_return
	frame_buffer_memory := gfx.arena_alloc(_ui.frame_buffer_memory, frame_buffer_size, frame_buffer_align) or_return
	_ui.frame_buffer = gfx.create_texture(frame_buffer_memory, frame_buffer_descriptor) or_return
	_ui.frame_buffer_view = gfx.default_view_of(_ui.frame_buffer) or_return

	depth_buffer_descriptor := gfx.Texture_Descriptor {
		type		= .D2_Array,
		dimensions	= { **_ui.screen_dimensions, 1 },
		format		= .D32_Float,
		sample_count	= 4,
		usage		= { .Depth_Stencil_Attachment },
	}
	depth_buffer_size, depth_buffer_align := gfx.size_align_of(depth_buffer_descriptor) or_return
	depth_buffer_memory := gfx.arena_alloc(_ui.frame_buffer_memory, depth_buffer_size, depth_buffer_align) or_return
	_ui.depth_buffer = gfx.create_texture(depth_buffer_memory, depth_buffer_descriptor) or_return
	_ui.depth_buffer_view = gfx.default_view_of(_ui.depth_buffer) or_return
	_ui.frame_buffer_resource_id = rd_acquire_texture_resource_id(rd_resource_manager(), .D2, _ui.frame_buffer_view)

	resolve_frame_buffer_descriptor := gfx.Texture_Descriptor {
		type		= .D2_Array,
		dimensions	= { **_ui.screen_dimensions, 1 },
		format		= .RGBA8_Unorm,
		sample_count	= 1,
		usage		= { .Color_Attachment, .Sampled },
	}
	resolve_frame_buffer_size, resolve_frame_buffer_align := gfx.size_align_of(resolve_frame_buffer_descriptor) or_return
	resolve_frame_buffer_memory := gfx.arena_alloc(_ui.frame_buffer_memory, resolve_frame_buffer_size, resolve_frame_buffer_align) or_return
	_ui.resolve_frame_buffer = gfx.create_texture(resolve_frame_buffer_memory, resolve_frame_buffer_descriptor) or_return
	_ui.resolve_frame_buffer_view = gfx.default_view_of(_ui.resolve_frame_buffer) or_return
	_ui.resolve_frame_buffer_resource_id = rd_acquire_texture_resource_id(rd_resource_manager(), .D2, _ui.resolve_frame_buffer_view)

	ui.SetLayoutDimensions({ **cast([2]f32)screen_size })

	return nil
}

ui_poll_inputs :: proc() {
	
	if !mouse_state.captured {
		ui.SetPointerState(
			{
				mouse_state.position.x,
				mouse_state.position.y,
			},
			.Pressed in mouse_state.buttons[.Left],
		)
	} else {
		ui.SetPointerState(
			{ -1, -1 },
			false,
		)
	}
}

ui_render :: proc(on_done: ..gfx.Semaphore_Signal) -> Result {
	
	render_commands := ui.EndLayout()

	command_buffer := gfx.begin_command_encoding(.Default) or_return

	renderpass_descriptor := gfx.Render_Pass_Descriptor {
		color_attachments	= []gfx.Render_Attachment {
			{
				view		= _ui.frame_buffer_view,
				resolve_view	= _ui.resolve_frame_buffer_view,
				load_operation	= .Clear,
				store_operation	= .Store,
				clear_value	= [4]f64 { 0.0, 0.0, 0.0, 0.0 },
			},
		},
		depth_attachment	= gfx.Render_Attachment{
			view		= _ui.depth_buffer_view,
			load_operation	= .Clear,
			store_operation	= .Store,
			clear_value	= 1.0,
		},
	}
	gfx.begin_render_pass(command_buffer, renderpass_descriptor) or_return
	gfx.use_resources(command_buffer, rd_current_resource_set_of(rd_resource_manager()))
	
	for i in 0..<render_commands.length {
		command := render_commands.internalArray[i]

		switch command.commandType {
		case .None:
		case .Rectangle:
			data := command.renderData.rectangle

			_ui_draw_rectangle(
				command_buffer,
				command,
				data,
			)

		case .Border:
			data := command.renderData.border

			_ui_draw_border(
				command_buffer,
				command,
				data,
			)

		case .Text:
			data := command.renderData.text

			if data.stringContents.length == 0 {
				continue
			}

			font_size := cast(f32)data.fontSize
			if font_size == 0 {
				font_size = 11
			}

			font, font_res := tx_instantiate_font(cast(int)data.fontId, font_size)
			if font_res != nil && font_res != .Exists_Already {
				continue
			}

			_ui_draw_text(
				command_buffer,
				font,
				ui.ToOdin(data.stringContents),
				data.textColor,
				{
					command.boundingBox.x,
					command.boundingBox.y + command.boundingBox.height,
				},
				command.zIndex,
			)

		case .Image:
		case .ScissorStart:
		case .ScissorEnd:
		case .Custom:
		}
	}

	gfx.end_render_pass(command_buffer) or_return
	gfx.submit(.Default, { command_buffer }, ..on_done) or_return

	ui.BeginLayout()

	return nil
}

_ui_report_error :: proc "c" (error: ui.ErrorData) {
	context		= runtime.default_context()
	context.logger	= _ui.error_logger

	log.errorf("[CLAY - %v] %s", error.errorType, error.errorText)
}

_ui_measure_text :: proc "c" (
	text:		ui.StringSlice,
	config:		^ui.TextElementConfig,
	user_data:	rawptr,
) -> ui.Dimensions {
	
	context		= runtime.default_context()
	context.logger	= _ui.error_logger

	if text.length == 0 {
		return {}
	}

	font_size := cast(f32)config.fontSize
	if font_size == 0 {
		font_size = 11
	}

	font, font_res := tx_instantiate_font(cast(int)config.fontId, font_size)
	if font_res != nil && font_res != .Exists_Already {
		log.errorf(
			"[CLAY - Measure Text] Could not instantiate a font (root: %d, size: %f). (Got error `%v`.)",
			config.fontId,
			font_size,
			font_res,
		)
		return {}
	}

	dimensions, dimensions_res := tx_dimensions_of(font, ui.ToOdin(text))
	if dimensions_res != nil {
		log.errorf(
			"[CLAY - Measure Text] Could not get the dimensions of a string. (Got error `%v`.)",
			dimensions_res,
		)
		
		return {}
	}

	if config.lineHeight != 0 {
		dimensions.y = cast(f32)config.lineHeight
	}

	return ui.Dimensions {
		width	= dimensions.x,
		height	= dimensions.y,
	}
}

_ui_Draw_Factor :: enum {
	Solid,
	Text,
	Texture,
}

_ui_Vertex :: struct #packed {
	position:	[2]f32,
	uv:		[2]f32,
}
#assert(size_of(_ui_Vertex) == 16)

_ui_Draw_Args :: struct #packed {
	vertices:		uintptr, // gpu [^]_ui_Vertex
	color:			[4]u8,
	texture:		u16,
	sampler:		u16,
	factors:		[_ui_Draw_Factor]u8,
	vertices_per_strip:	u8,
	z_index:		i16,
}
#assert(size_of(_ui_Draw_Args) == 22)

_ui_screen_to_ndc :: proc(position: [2]f32) -> [2]f32 {
	return {
		((position.x / cast(f32)_ui.screen_dimensions.x) - 0.5) * 2,
		((position.y / cast(f32)_ui.screen_dimensions.y) - 0.5) * 2,
	}
}

_ui_generate_border_strips :: proc(
	vertices:	^[dynamic]_ui_Vertex,
	center:		[2]f32,
	corner_radius:	f32,
	start_theta:	f32,
	end_theta:	f32,
) {
	assert(start_theta <= end_theta)

	steps :: 8

	dtheta := (end_theta - start_theta) / steps

	prev_pos := [2]f32 {
		math.cos(start_theta),
		-math.sin(start_theta),
	} * corner_radius / cast([2]f32)_ui.screen_dimensions * 2
	prev_pos = center + prev_pos
	theta := start_theta + dtheta

	for _ in 0..<steps {
		offset := [2]f32{
			math.cos(theta),
			-math.sin(theta),
		} * corner_radius / cast([2]f32)_ui.screen_dimensions * 2
		position := center + offset

		append(vertices, _ui_Vertex {
			position	= center,
		})
		append(vertices, _ui_Vertex {
			position	= prev_pos,
		})
		append(vertices, _ui_Vertex {
			position	= position,
		})

		prev_pos = position
		theta += dtheta
	}
}

_ui_draw_border :: proc(
	command_buffer:	gfx.Command_Buffer,
	command:	ui.RenderCommand,
	data:		ui.BorderRenderData,
) -> Result {

	outer_bottom_left := _ui_screen_to_ndc({
		command.boundingBox.x,
		command.boundingBox.y + command.boundingBox.height,
	})
	outer_bottom_right := _ui_screen_to_ndc({
		command.boundingBox.x + command.boundingBox.width,
		command.boundingBox.y + command.boundingBox.height,
	})
	outer_top_left := _ui_screen_to_ndc({
		command.boundingBox.x,
		command.boundingBox.y,
	})
	outer_top_right := _ui_screen_to_ndc({
		command.boundingBox.x + command.boundingBox.width,
		command.boundingBox.y,
	})

	inner_bottom_left := _ui_screen_to_ndc({
		command.boundingBox.x + data.cornerRadius.bottomLeft,
		command.boundingBox.y + command.boundingBox.height - data.cornerRadius.bottomLeft,
	})
	inner_bottom_right := _ui_screen_to_ndc({
		command.boundingBox.x + command.boundingBox.width - data.cornerRadius.bottomRight,
		command.boundingBox.y + command.boundingBox.height - data.cornerRadius.bottomRight,
	})
	inner_top_left := _ui_screen_to_ndc({
		command.boundingBox.x + data.cornerRadius.topLeft,
		command.boundingBox.y + data.cornerRadius.topLeft,
	})
	inner_top_right := _ui_screen_to_ndc({
		command.boundingBox.x + command.boundingBox.width - data.cornerRadius.topRight,
		command.boundingBox.y + data.cornerRadius.topRight,
	})

	quad_strips := make([dynamic]_ui_Vertex, context.temp_allocator)
	// Left outer quad
	if inner_bottom_left.x != outer_bottom_left.x || inner_top_left.x != outer_top_left.x {

		append(&quad_strips, _ui_Vertex {
			position	= { outer_bottom_left.x, inner_bottom_left.y },
		})
		append(&quad_strips, _ui_Vertex {
			position	= inner_bottom_left,
		})
		append(&quad_strips, _ui_Vertex {
			position	= { outer_top_left.x, inner_top_left.y },
		})
		append(&quad_strips, _ui_Vertex {
			position	= inner_top_left,
		})
	}
	// Right outer quad
	if inner_bottom_right.x != outer_bottom_right.x || inner_top_right.x != outer_top_right.x {

		append(&quad_strips, _ui_Vertex {
			position	= { outer_bottom_right.x, inner_bottom_right.y },
		})
		append(&quad_strips, _ui_Vertex {
			position	= inner_bottom_right,
		})
		append(&quad_strips, _ui_Vertex {
			position	= { outer_top_right.x, inner_top_right.y },
		})
		append(&quad_strips, _ui_Vertex {
			position	= inner_top_right,
		})
	}
	// Top outer quad
	if inner_top_left.y != outer_top_left.y || inner_top_right.y != outer_top_right.y {
		append(&quad_strips, _ui_Vertex {
			position	= inner_top_left,
		})
		append(&quad_strips, _ui_Vertex {
			position	= inner_top_right,
		})
		append(&quad_strips, _ui_Vertex {
			position	= { inner_top_left.x, outer_top_left.y },
		})
		append(&quad_strips, _ui_Vertex {
			position	= { inner_top_right.x, outer_top_right.y },
		})
	}
	// Bottom outer quad
	if inner_bottom_left.y != outer_bottom_left.y || inner_bottom_right.y != outer_bottom_right.y {
		append(&quad_strips, _ui_Vertex {
			position	= { inner_bottom_left.x, outer_bottom_left.y },
		})
		append(&quad_strips, _ui_Vertex {
			position	= { inner_bottom_right.x, outer_bottom_right.y },
		})
		append(&quad_strips, _ui_Vertex {
			position	= inner_bottom_left,
		})
		append(&quad_strips, _ui_Vertex {
			position	= inner_bottom_right,
		})
	}

	border_strips := make([dynamic]_ui_Vertex, context.temp_allocator)
	// Bottom Left border
	if inner_bottom_left != outer_bottom_left {
		_ui_generate_border_strips(
			&border_strips,
			inner_bottom_left,
			data.cornerRadius.bottomLeft,
			math.PI,
			3.0/2.0 * math.PI,
		)
	}
	// Bottom Right border
	if inner_bottom_right != outer_bottom_right {
		_ui_generate_border_strips(
			&border_strips,
			inner_bottom_right,
			data.cornerRadius.bottomLeft,
			3.0/2.0 * math.PI,
			2.0 * math.PI,
		)
	}
	// Top Left border
	if inner_top_left != outer_top_left {
		_ui_generate_border_strips(
			&border_strips,
			inner_top_left,
			data.cornerRadius.topLeft,
			1.0/2.0 * math.PI,
			math.PI,
		)
	}
	// Top Right border
	if inner_top_right != outer_top_right {
		_ui_generate_border_strips(
			&border_strips,
			inner_top_right,
			data.cornerRadius.topLeft,
			0.0,
			1.0/2.0 * math.PI,
		)
	}

	_ui_draw(command_buffer, .Solid, quad_strips[:], 4, len(quad_strips) / 4, data.color, 0, command.zIndex) or_return
	_ui_draw(command_buffer, .Solid, border_strips[:], 3, len(border_strips) / 3, data.color, 0, command.zIndex) or_return

	return nil
}

_ui_draw_rectangle :: proc(
	command_buffer:	gfx.Command_Buffer,
	command:	ui.RenderCommand,
	data:		ui.RectangleRenderData,
) -> Result {

	outer_bottom_left := _ui_screen_to_ndc({
		command.boundingBox.x,
		command.boundingBox.y + command.boundingBox.height,
	})
	outer_bottom_right := _ui_screen_to_ndc({
		command.boundingBox.x + command.boundingBox.width,
		command.boundingBox.y + command.boundingBox.height,
	})
	outer_top_left := _ui_screen_to_ndc({
		command.boundingBox.x,
		command.boundingBox.y,
	})
	outer_top_right := _ui_screen_to_ndc({
		command.boundingBox.x + command.boundingBox.width,
		command.boundingBox.y,
	})

	inner_bottom_left := _ui_screen_to_ndc({
		command.boundingBox.x + data.cornerRadius.bottomLeft,
		command.boundingBox.y + command.boundingBox.height - data.cornerRadius.bottomLeft,
	})
	inner_bottom_right := _ui_screen_to_ndc({
		command.boundingBox.x + command.boundingBox.width - data.cornerRadius.bottomRight,
		command.boundingBox.y + command.boundingBox.height - data.cornerRadius.bottomRight,
	})
	inner_top_left := _ui_screen_to_ndc({
		command.boundingBox.x + data.cornerRadius.topLeft,
		command.boundingBox.y + data.cornerRadius.topLeft,
	})
	inner_top_right := _ui_screen_to_ndc({
		command.boundingBox.x + command.boundingBox.width - data.cornerRadius.topRight,
		command.boundingBox.y + data.cornerRadius.topRight,
	})

	quad_strips := make([dynamic]_ui_Vertex, context.temp_allocator)
	// Inner quad
	{
		append(&quad_strips, _ui_Vertex {
			position	= inner_bottom_left,
		})
		append(&quad_strips, _ui_Vertex {
			position	= inner_bottom_right,
		})
		append(&quad_strips, _ui_Vertex {
			position	= inner_top_left,
		})
		append(&quad_strips, _ui_Vertex {
			position	= inner_top_right,
		})
	}
	// Left outer quad
	if inner_bottom_left.x != outer_bottom_left.x || inner_top_left.x != outer_top_left.x {

		append(&quad_strips, _ui_Vertex {
			position	= { outer_bottom_left.x, inner_bottom_left.y },
		})
		append(&quad_strips, _ui_Vertex {
			position	= inner_bottom_left,
		})
		append(&quad_strips, _ui_Vertex {
			position	= { outer_top_left.x, inner_top_left.y },
		})
		append(&quad_strips, _ui_Vertex {
			position	= inner_top_left,
		})
	}
	// Right outer quad
	if inner_bottom_right.x != outer_bottom_right.x || inner_top_right.x != outer_top_right.x {

		append(&quad_strips, _ui_Vertex {
			position	= { outer_bottom_right.x, inner_bottom_right.y },
		})
		append(&quad_strips, _ui_Vertex {
			position	= inner_bottom_right,
		})
		append(&quad_strips, _ui_Vertex {
			position	= { outer_top_right.x, inner_top_right.y },
		})
		append(&quad_strips, _ui_Vertex {
			position	= inner_top_right,
		})
	}
	// Top outer quad
	if inner_top_left.y != outer_top_left.y || inner_top_right.y != outer_top_right.y {
		append(&quad_strips, _ui_Vertex {
			position	= inner_top_left,
		})
		append(&quad_strips, _ui_Vertex {
			position	= inner_top_right,
		})
		append(&quad_strips, _ui_Vertex {
			position	= { inner_top_left.x, outer_top_left.y },
		})
		append(&quad_strips, _ui_Vertex {
			position	= { inner_top_right.x, outer_top_right.y },
		})
	}
	// Bottom outer quad
	if inner_bottom_left.y != outer_bottom_left.y || inner_bottom_right.y != outer_bottom_right.y {
		append(&quad_strips, _ui_Vertex {
			position	= { inner_bottom_left.x, outer_bottom_left.y },
		})
		append(&quad_strips, _ui_Vertex {
			position	= { inner_bottom_right.x, outer_bottom_right.y },
		})
		append(&quad_strips, _ui_Vertex {
			position	= inner_bottom_left,
		})
		append(&quad_strips, _ui_Vertex {
			position	= inner_bottom_right,
		})
	}

	border_strips := make([dynamic]_ui_Vertex, context.temp_allocator)
	// Bottom Left border
	if inner_bottom_left != outer_bottom_left {
		_ui_generate_border_strips(
			&border_strips,
			inner_bottom_left,
			data.cornerRadius.bottomLeft,
			math.PI,
			3.0/2.0 * math.PI,
		)
	}
	// Bottom Right border
	if inner_bottom_right != outer_bottom_right {
		_ui_generate_border_strips(
			&border_strips,
			inner_bottom_right,
			data.cornerRadius.bottomRight,
			3.0/2.0 * math.PI,
			2.0 * math.PI,
		)
	}
	// Top Left border
	if inner_top_left != outer_top_left {
		_ui_generate_border_strips(
			&border_strips,
			inner_top_left,
			data.cornerRadius.topLeft,
			1.0/2.0 * math.PI,
			math.PI,
		)
	}
	// Top Right border
	if inner_top_right != outer_top_right {
		_ui_generate_border_strips(
			&border_strips,
			inner_top_right,
			data.cornerRadius.topRight,
			0.0,
			1.0/2.0 * math.PI,
		)
	}

	_ui_draw(command_buffer, .Solid, quad_strips[:], 4, len(quad_strips) / 4, data.backgroundColor, 0, command.zIndex) or_return
	_ui_draw(command_buffer, .Solid, border_strips[:], 3, len(border_strips) / 3, data.backgroundColor, 0, command.zIndex) or_return

	return nil
}

_ui_draw_text :: proc(
	command_buffer:	gfx.Command_Buffer,
	font:		tx_Font,
	text:		string,
	color:		[4]f32,
	position:	[2]f32,
	z_index:	i16,
) -> Result {

	vertices	:= make([dynamic]_ui_Vertex, context.temp_allocator) or_return
	glyph_count	:= 0
	atlas_texture	:= 0

	iter := tx_make_glyph_iterator(font, text, position.xy) or_return
	for glyph_info, cursor in tx_iterate_glyph(&iter) {

		bottom_left := _ui_screen_to_ndc({
			cursor.x + glyph_info.offset.x,
			cursor.y + glyph_info.offset.y,
		})
		top_right := _ui_screen_to_ndc({
			cursor.x + glyph_info.offset.x + cast(f32)glyph_info.dimensions.x,
			cursor.y + glyph_info.offset.y + cast(f32)glyph_info.dimensions.y,
		})
		
		x0 := bottom_left.x
		y0 := bottom_left.y
		x1 := top_right.x
		y1 := top_right.y

		u0 := cast(f32)(glyph_info.atlas_position.x) / tx_FONT_ATLAS_SIZE
		u1 := cast(f32)(glyph_info.atlas_position.x + glyph_info.atlas_size.x) / tx_FONT_ATLAS_SIZE
		v0 := cast(f32)(glyph_info.atlas_position.y) / tx_FONT_ATLAS_SIZE
		v1 := cast(f32)(glyph_info.atlas_position.y + glyph_info.atlas_size.y) / tx_FONT_ATLAS_SIZE

		// Bottom Left
		append(&vertices, _ui_Vertex {
			position	= { x0, y0 },
			uv		= { u0, v0 },
		}) or_return
		// Bottom Right
		append(&vertices, _ui_Vertex {
			position	= { x1, y0 },
			uv		= { u1, v0 },
		}) or_return
		// Top Left
		append(&vertices, _ui_Vertex {
			position	= { x0, y1 },
			uv		= { u0, v1 },
		}) or_return
		// Top Right
		append(&vertices, _ui_Vertex {
			position	= { x1, y1 },
			uv		= { u1, v1 },
		}) or_return

		glyph_count	+= 1
		atlas_texture	= glyph_info.atlas_resource_index
	}

	_ui_draw(command_buffer, .Text, vertices[:], 4, glyph_count, color, atlas_texture, z_index)

	return nil
}

// Draws the provided vertices as triangle strips with the specified draw mode.
//
// Modes:
//	- Solid: 	out = color
//	- Text:		out = (color.xyz, sample(texture).r)
//	- Texture:	out = sample(texture).rgba
_ui_draw :: proc(
	command_buffer:		gfx.Command_Buffer,
	mode:			_ui_Draw_Factor,
	vertices:		[]_ui_Vertex,
	vertices_per_strip:	int,
	strips:			int,
	color:			[4]f32,
	texture:		int,
	z_index:		i16,
) -> Result {

	assert(len(vertices) == vertices_per_strip * strips)
	assert(vertices_per_strip <= 255)

	if len(vertices) == 0 {
		return nil
	}

	staging_vertices := gfx.scratch_alloc(_ui.frame_memory, []_ui_Vertex, len(vertices)) or_return
	gpu_vertices := gfx.gpu_address_of(raw_data(staging_vertices)) or_return
	copy(staging_vertices, vertices)

	norm_color := cast([4]u8)color

	draw_args := gfx.scratch_alloc(_ui.frame_memory, _ui_Draw_Args) or_return
	draw_args^ = {
		vertices		= gpu_vertices,
		color			= norm_color,
		texture			= cast(u16)texture,
		sampler			= cast(u16)_ui.sampler_resource_id,
		vertices_per_strip	= cast(u8)vertices_per_strip,
		z_index			= z_index,
		factors			= {
			.Solid		= mode == .Solid   ? 1 : 0,
			.Text		= mode == .Text    ? 1 : 0,
			.Texture	= mode == .Texture ? 1 : 0,
		},
	}
	gfx.draw(command_buffer, _ui.pipeline, draw_args, vertices_per_strip, strips) or_return

	return nil
}

