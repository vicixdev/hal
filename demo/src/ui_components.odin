package main

import ui "shared:clay"

ui_Window_Status :: enum {
	Normal,
	Closed,
	Dragged,
	Resizing,
}

ui_Window_Persistent_Data :: struct {
	position:		[2]f32,
	dimensions:		[2]f32,
	contents_hidden:	bool,
	status:			ui_Window_Status,

	_start_position:	[2]f32,
	_start_dimensions:	[2]f32,
	_start_cursor_position:	[2]f32,
	_did_close_this_frame:	bool,
}
ui_Window_Config :: struct {
	using	persistent:	^ui_Window_Persistent_Data,
	min_dimensions:		[2]f32,
	title:			string,
}
@(deferred_in=_ui_close_window)
ui_Window :: proc(id: ui.ElementId, config: ^ui_Window_Config) -> bool {

	TITLE_BAR		:= ui.PRIMARY_800
	TITLE_BAR_BORDER	:= ui.PRIMARY_700
	CONTENTS		:= ui.NEUTRAL_800
	CONTENTS_BORDER		:= ui.NEUTRAL_700
	TEXT			:= ui.Font()

	WINDOW_CORNER_RADIUS	:: 10
	TITLE_BAR_HEIGHT	:: 20
	MIN_WINDOW_DIMENSIONS	:: [2]f32{ 80, 32 }

	config._did_close_this_frame = false

	pointer_state := ui.GetPointerState()
	#partial switch config.status {
	case .Dragged:
		delta := mouse_state.position - config._start_cursor_position
		config.position = config._start_position + delta

		if pointer_state.state == .Released {
			config.status = .Normal
		}

	case .Resizing:
		delta := mouse_state.position - config._start_cursor_position
		config.dimensions = config._start_dimensions + delta

		if pointer_state.state == .Released {
			config.status = .Normal
		}

	case .Closed:
		return false
	}

	config.dimensions.x = max(config.dimensions.x, config.min_dimensions.x, MIN_WINDOW_DIMENSIONS.x)
	config.dimensions.y = max(config.dimensions.y, config.min_dimensions.y, MIN_WINDOW_DIMENSIONS.y)

	ui._OpenElementWithId(id)
	ui.ConfigureOpenElement({
		layout	= {
			sizing	= { ui.SizingFixed(config.dimensions.x), ui.SizingFixed(config.dimensions.y) },
			layoutDirection	= .TopToBottom,
		},
		floating = {
			offset		= config.position,
			attachment	= {
				element	= .LeftTop,
				parent	= .LeftTop,
			},
			pointerCaptureMode = .Capture,
			attachTo	= .Root,
		},
	})

	if ui.UI(ui.ID_LOCAL("Window:title_bar"))({
		layout = {
			sizing		= { ui.SizingGrow(), ui.SizingFixed(TITLE_BAR_HEIGHT) },
			layoutDirection = .LeftToRight,
			padding		= { WINDOW_CORNER_RADIUS / 3, WINDOW_CORNER_RADIUS / 3, 0, 0 },
			childGap	= 5,
		},
		backgroundColor	= TITLE_BAR,
		border		= {
			color	= TITLE_BAR_BORDER,
			width	= { 1, 1, 1, 0, 0 },
		},
		cornerRadius	= { WINDOW_CORNER_RADIUS, WINDOW_CORNER_RADIUS, 0, 0 },
	}) {

		if ui.UI(ui.ID_LOCAL("Window:title"))({
			layout = {
				sizing		= { ui.SizingGrow({}), ui.SizingGrow({}) },
				padding		= { 5, 0, 0, 0 },
				childAlignment = { .Left, .Center },
			},
			clip		= {
				horizontal	= true,
			},
		}) {
			ui.TextDynamic(config.title, TEXT)

			if ui.Hovered() && pointer_state.state == .PressedThisFrame {
				config._start_position	= config.position
				config._start_cursor_position	= pointer_state.position
				config.status			= .Dragged
			}
		}

		if ui.UI(ui.ID_LOCAL("Window:semaphore_buttons"))({
			layout = {
				sizing = { ui.SizingFit(), ui.SizingGrow({}) },
				childAlignment = { .Center, .Center },
				padding = ui.PaddingAll(2),
				childGap = 5,
			},
		}) {

			if ui_Bulb_Button(ui.ID_LOCAL("Window:hide_bulb"), {
				symbol		= .Horizontal_Line,
				color		= ui.Color{ 210, 210, 210, 255 },
				border_color	= ui.Color{ 170, 170, 170, 255 },
				symbol_color	= ui.Color{ 100, 100, 100, 255 },
			}) {
				if config.status == .Normal {
					config.contents_hidden = !config.contents_hidden
				}
			}

			if ui_Bulb_Button(ui.ID_LOCAL("Window:close_bulb"), {
				symbol		= .Dot,
				color		= ui.Color{ 255, 0, 0, 255 },
				border_color	= ui.Color{ 200, 0, 0, 255 },
				symbol_color	= ui.Color{ 125, 0, 0, 255 },
			}) {
				if config.status == .Normal {
					config.status	= .Closed
					config._did_close_this_frame	= true

					return false
				}
			}
		}
	}

	if config.contents_hidden {
		return false
	}

	contents_id := ui.ID_LOCAL("Window:contents")
	ui._OpenElementWithId(contents_id)
	ui.ConfigureOpenElement({
		layout	= {
			sizing	= { ui.SizingGrow(), ui.SizingGrow() },
			layoutDirection	= .TopToBottom,
		},
		backgroundColor = CONTENTS,
		border		= {
			color	= CONTENTS_BORDER,
			width	= { 1, 1, 0, 1, 0 },
		},
		clip		= {
			horizontal	= true,
			vertical	= true,
			childOffset	= ui.GetScrollOffset(),
		},
	})

	resize_box_id := ui.ID_LOCAL("Window:resize_box")
	resize_box_color := ui.Color{ 0, 0, 0, 0 }
	if config.status == .Resizing {
		resize_box_color = ui.PRIMARY_900
	} else if ui.PointerOver(resize_box_id) {
		resize_box_color = TITLE_BAR
	}

	if ui.UI(resize_box_id)({
		layout	= {
			sizing	= { ui.SizingFixed(12), ui.SizingFixed(12) },
		},
		cornerRadius	= { 5, 0, 0, 0 },
		backgroundColor = resize_box_color,
		floating	= {
			attachment	= {
				element	= .RightBottom,
				parent	= .RightBottom,
			},
			parentId	= contents_id.id,
			attachTo	= .Parent,
			clipTo		= .AttachedParent,
			pointerCaptureMode = .Capture,
		},
	}) {
		if ui.Hovered() && pointer_state.state == .PressedThisFrame {
			config._start_dimensions	= config.dimensions
			config._start_cursor_position	= pointer_state.position
			config.status = .Resizing
		}
	}

	if config.status == .Resizing {
		if ui.UI(ui.ID_LOCAL("Window:interaction_blocker"))({
			layout = {
				sizing = { ui.SizingFixed(config.dimensions.x), ui.SizingFixed(config.dimensions.y - TITLE_BAR_HEIGHT) },
			},
			floating	= {
				attachment	= {
					element	= .LeftTop,
					parent	= .LeftTop,
				},
				parentId	= contents_id.id,
				attachTo	= .Parent,
				clipTo		= .AttachedParent,
				pointerCaptureMode = .Capture,
			},
		}) {}
	}

	return true
}
_ui_close_window :: proc(id: ui.ElementId, config: ^ui_Window_Config) {
	if config._did_close_this_frame {
		// Window
		ui._CloseElement()
	} else if config.status != .Closed {
		if !config.contents_hidden {
			// Window:Contents
			ui._CloseElement()
		}

		// Window
		ui._CloseElement()
	}
}

ui_Icon_Type :: enum {
	Dot,
	Horizontal_Line,
	Vertical_Line,
}
ui_Icon_Config :: struct {
	type:	ui_Icon_Type,
	color:	[4]f32,
	size:	f32,
}
ui_Icon :: proc(id: ui.ElementId, config: ui_Icon_Config) {
	switch config.type {
	case .Dot:
		if ui.UI(id)({
			layout	= {
				sizing	= { ui.SizingFixed(config.size), ui.SizingFixed(config.size) },
			},
			cornerRadius	= ui.CornerRadiusAll(config.size / 2),
			backgroundColor	= config.color,
		}) {}

	case .Horizontal_Line:
		if ui.UI(id)({
			layout	= {
				sizing	= { ui.SizingFixed(config.size * 2), ui.SizingFixed(config.size * 0.75) },
			},
			cornerRadius	= ui.CornerRadiusAll(config.size * 0.75 / 2),
			backgroundColor	= config.color,
		}) {}

	case .Vertical_Line:
		if ui.UI(id)({
			layout	= {
				sizing	= { ui.SizingFixed(config.size * 0.75), ui.SizingFixed(config.size * 2) },
			},
			cornerRadius	= ui.CornerRadiusAll(config.size * 0.75 / 2),
			backgroundColor	= config.color,
		}) {}
	}
}

// It's a light bulb button, like, in the semaphores. :-)
ui_Buld_Button_Config :: struct {
	symbol:		ui_Icon_Type,

	color:		[4]f32,
	border_color:	[4]f32,
	symbol_color:	[4]f32,
}
ui_Bulb_Button :: proc(id: ui.ElementId, config: ui_Buld_Button_Config) -> bool {

	BUTTON_SIZE :: 12

	color := config.color

	pointer_state := ui.GetPointerState()
	if ui.PointerOver(id) && (pointer_state.state == .Pressed || pointer_state.state == .PressedThisFrame) {
		color = config.border_color
	}

	if ui.UI(id)({
		layout = {
			sizing = { ui.SizingFixed(BUTTON_SIZE), ui.SizingFixed(BUTTON_SIZE) },
			childAlignment = { .Center, .Center },
		},
		cornerRadius = ui.CornerRadiusAll(BUTTON_SIZE / 2),
		backgroundColor = color,
		border = {
			color = config.border_color,
			width = ui.BorderAll(1),
		},
	}) {
		if ui.Hovered() {
			ui_Icon(ui.ID_LOCAL("Bulb_Button:Symbol"), {
				type	= config.symbol,
				color	= config.symbol_color,
				size	= 4,
			})
			
			if pointer_state.state == .ReleasedThisFrame {
				return true
			}
		}
	}

	return false
}

ui_Accordion_Config :: struct {
	title:		string,

	color:		[4]f32,
	hovered_color:	[4]f32,
	details_color:	[4]f32,
	title_color:	[4]f32,

	open:		^bool,
}
@(deferred_out=_ui_close_accordion)
ui_Accordion :: proc(id: ui.ElementId, config: ui_Accordion_Config) -> bool {

	pointer_state := ui.GetPointerState()

	ui._OpenElementWithId(id)
	
	ui.ConfigureOpenElement({
		layout	= {
			sizing	= { ui.SizingGrow(), ui.SizingFit() },
			layoutDirection = .TopToBottom,
		},
	})

	if ui.UI(ui.ID_LOCAL("Accordion:heading"))({
		layout	= {
			sizing	= { ui.SizingGrow(), ui.SizingFixed(30) },
			padding	= { 5, 5, 2, 1 },
			childGap = 5,
			childAlignment = { .Left, .Center },
			layoutDirection = .LeftToRight,
		},
		backgroundColor	= config.open^ || ui.Hovered() ? config.hovered_color : config.color,
	}) {
		if ui.UI(ui.ID_LOCAL("Accordion:status_container"))({
			layout	= {
				sizing	= { ui.SizingFixed(10), ui.SizingFixed(10) },
				childAlignment = { .Center, .Center },
			},
			border	= {
				color	= config.details_color,
				width	= { 1, 1, 1, 1, 0 },
			},
			cornerRadius = ui.CornerRadiusAll(5),
		}) {
			if config.open^ {
				ui_Icon(ui.ID_LOCAL("Accordion:status"), {
					type	= .Horizontal_Line,
					color	= config.details_color,
					size	= 2,
				})
			} else {
				ui_Icon(ui.ID_LOCAL("Accordion:status"), {
					type	= .Vertical_Line,
					color	= config.details_color,
					size	= 2,
				})
			}
		}

		ui.TextDynamic(config.title, ui.Font(color=config.title_color))

		if ui.Hovered() && pointer_state.state == .ReleasedThisFrame {
			config.open^ = !config.open^
		}
	}
	
	if config.open^ {
		ui._OpenElementWithId(ui.ID_LOCAL("Accordion:contents"))
		ui.ConfigureOpenElement({
			layout	= {
				sizing	= { ui.SizingGrow(), ui.SizingFit() },
				layoutDirection = .TopToBottom,
				padding	= { 5, 5, 3, 3 },
			},
		})
	}

	return config.open^
}
_ui_close_accordion :: proc(is_open: bool) {
	if is_open {
		// Accordion:contents
		ui._CloseElement()
	}
	// Accordion
	ui._CloseElement()
}

