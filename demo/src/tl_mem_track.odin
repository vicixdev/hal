package main

import "base:runtime"
import "core:mem"
import "core:fmt"
import "core:strings"
import vmem "core:mem/virtual"
import ui "shared:clay"
import "root:gfx"
import gmem "root:gfx/mem"

tl_Tracked_Memory_Target :: union #no_nil {
	^mem.Arena,
	^mem.Scratch,
	^gmem.Scratch,
	^vmem.Arena,
	^gfx.Arena,
	^gfx.Scratch,
}

tl_Tracked_Memory :: struct {
	label:		string,
	target:		tl_Tracked_Memory_Target,

	start:		int,
	next_start:	int,
	end:		int,
	max:		int,

	ui_open:	bool,
}

tl_track_allocator:	runtime.Allocator
tl_tracked_memories:	[dynamic]tl_Tracked_Memory

tl_init_memtrack :: proc(allocator := context.allocator) {
	tl_track_allocator = allocator
	tl_tracked_memories = make([dynamic]tl_Tracked_Memory, allocator)
}

tl_fini_memtrack :: proc() {
	for memory in tl_tracked_memories {
		delete(memory.label, tl_track_allocator)
	}

	delete(tl_tracked_memories)
}

tl_track_memory :: proc(label: string, target: tl_Tracked_Memory_Target) {
	append(&tl_tracked_memories, tl_Tracked_Memory {
		label	= strings.clone(label, tl_track_allocator),
		target	= target,
	})
}

tl_begin_frame :: proc() {
	for &memory in tl_tracked_memories {
		switch v in memory.target {
		case ^mem.Arena:
			memory.next_start = v.offset

		case ^mem.Scratch:
			memory.next_start = v.curr_offset

		case ^gmem.Scratch:
			memory.next_start = v.curr_offset

		case ^vmem.Arena:
			memory.next_start = cast(int)v.total_used

		case ^gfx.Arena:
			memory.next_start = v.offset

		case ^gfx.Scratch:
			memory.next_start = v.offset
		}
	}
}

tl_end_frame :: proc() {
	for &memory in tl_tracked_memories {
		switch v in memory.target {
		case ^mem.Arena:
			memory.end = v.offset
			memory.max = len(v.data)

		case ^mem.Scratch:
			memory.end = v.curr_offset
			memory.max = len(v.data)

		case ^gmem.Scratch:
			memory.end = v.curr_offset
			memory.max = len(v.data)

		case ^vmem.Arena:
			memory.end = cast(int)v.total_used
			memory.max = cast(int)v.total_reserved

		case ^gfx.Arena:
			memory.end = v.offset
			memory.max = v.size

		case ^gfx.Scratch:
			memory.end = v.offset
			memory.max = v.size
		}

		memory.start = memory.next_start
	}
}

tl_track_internal_gfx_memory :: proc() {
	tl_track_memory("gfx::_global_arena",	&gfx._global_arena)
	tl_track_memory("gfx::_temp_scratch",	&gfx._temp_scratch)

	for &command_buffer, i in gfx._command_buffers[.Default] {
		label := fmt.tprintf("gfx::_command_buffers[.Default][%v]", i)
		tl_track_memory(label, &command_buffer.arena)
	}
	if gfx._device_info.properties.transfer_queue {
		for &command_buffer, i in gfx._command_buffers[.Transfer] {
			label := fmt.tprintf("gfx::_command_buffers[.Transfer][%v]", i)
			tl_track_memory(label, &command_buffer.arena)
		}
	}
}

tl_Memory_Tracker :: proc() {

	if ui.UI(ui.ID("Memory tracker"))(ui.ElementDeclaration {
		layout	= {
			sizing	= {
				ui.SizingGrow(),
				ui.SizingGrow(),
			},
			layoutDirection	= .TopToBottom,
		},
		border = {
			color = ui.PRIMARY_700,
			width = { 0, 0, 0, 0, 1 },
		},
	}) {
		for &memory, i in tl_tracked_memories {

			if ui_Accordion(ui.ID_LOCAL("Tracked Memory", i), {
				title		= memory.label,
				color		= ui.NEUTRAL_800,
				hovered_color	= ui.PRIMARY_700,
				details_color	= ui.PRIMARY_300,
				title_color	= ui.WHITE,
				open		= &memory.ui_open,
			}) {
				
				info := _tl_memory_target_info(memory)

				if ui.UI(ui.ID_LOCAL("Property table"))({
					layout = {
						sizing	= { ui.SizingFit(), ui.SizingFit() },
						layoutDirection = .LeftToRight,
						childGap	= 5,
					},
				}) {
					if ui.UI(ui.ID_LOCAL("Property Names"))({
						layout = {
							sizing	= { ui.SizingFit(), ui.SizingFit() },
							layoutDirection = .TopToBottom,
						},
					}) {
						ui.Text("STRUCTURE", ui.Font())
						ui.Text("TYPE", ui.Font())
						ui.Text("AVAILABLE", ui.Font())
						ui.Text("USED", ui.Font())
						ui.Text("USED THIS FRAME", ui.Font())
					}
					if ui.UI(ui.ID_LOCAL("Property Values"))({
						layout = {
							sizing	= { ui.SizingFit(), ui.SizingGrow() },
							layoutDirection = .TopToBottom,
						},
					}) {
						ui.TextDynamic(fmt.tprintf("%s", info.structure), ui.Font())
						ui.TextDynamic(fmt.tprintf("%s", info.type), ui.Font())
						ui.TextDynamic(fmt.tprintf("%d bytes", info.available), ui.Font())
						ui.TextDynamic(fmt.tprintf("%d bytes (%.2f%%)", info.used, info.percent), ui.Font())
						ui.TextDynamic(fmt.tprintf("%d bytes (%.2f%%)", info.used_this_frame, info.percent_this_frame), ui.Font())
					}
				}

				if ui.UI(ui.ID_LOCAL("Usage Bar"))(ui.ElementDeclaration{
					layout = {
						sizing	= {
							ui.SizingGrow(),
							ui.SizingFixed(20),
						},
						layoutDirection	= .LeftToRight,
						padding = { 0, 0, 5, 3 },
					},
				}) {
					
					tot := cast(f32)(info.available)
					p0 := cast(f32)(info.start) / tot
					p1 := cast(f32)(info.frame_start - info.start) / tot
					p2 := cast(f32)(info.end - info.frame_start) / tot
					p3 := cast(f32)(info.available - info.end) / tot

					if ui.UI(ui.ID_LOCAL("Free at start"))(ui.ElementDeclaration {
						layout	= {
							sizing	= {
								ui.SizingPercent(p0),
								ui.SizingGrow(),
							},
						},
						backgroundColor	= { 125, 125, 125, 255 },
					}) {}
					if ui.UI(ui.ID_LOCAL("Used"))(ui.ElementDeclaration {
						layout	= {
							sizing	= {
								ui.SizingPercent(p1),
								ui.SizingGrow(),
							},
						},
						backgroundColor = { 100, 25, 25, 255 },
					}) {}
					if ui.UI(ui.ID_LOCAL("Used this frame"))(ui.ElementDeclaration {
						layout	= {
							sizing	= {
								ui.SizingPercent(p2),
								ui.SizingGrow(),
							},
						},
						backgroundColor	= { 255, 255, 0, 255 },
					}) {}
					if ui.UI(ui.ID_LOCAL("Free at end"))(ui.ElementDeclaration {
						layout	= {
							sizing	= {
								ui.SizingPercent(p3),
								ui.SizingGrow(),
							},
						},
						backgroundColor	= { 100, 100, 100, 255 },
					}) {}
				}
			}
		}
	}
}

_tl_Memory_Target_Info :: struct {
	structure:		string,
	type:			string,
	available:		int,
	used:			int,
	used_this_frame:	int,
	percent:		f32,
	percent_this_frame:	f32,
	start:			int,
	frame_start:		int,
	end:			int,
}

_tl_memory_target_info :: proc(memory: tl_Tracked_Memory) -> (info: _tl_Memory_Target_Info) {
	switch v in memory.target {
	case ^mem.Arena:
		info.structure	= "mem::Arena"
		info.type	= "Cpu memory"
		info.used	= memory.end
		info.available	= memory.max - memory.end
		info.start	= 0

	case ^mem.Scratch:
		info.structure	= "mem::Scratch"
		info.type	= "Cpu memory"
		info.used	= memory.end - memory.start
		info.available	= memory.max - info.used
		info.start	= memory.start

	case ^gmem.Scratch:
		info.structure	= "vicixdev_gfx_mem::Scratch"
		info.type	= "Cpu memory"
		info.used	= memory.end - memory.start
		info.available	= memory.max - info.used
		info.start	= memory.start

	case ^vmem.Arena:
		info.structure	= "mem_virtual::Arena"
		info.type	= "Cpu memory"
		info.used	= memory.end
		info.available	= memory.max - memory.end
		info.start	= 0

	case ^gfx.Arena:
		info.structure	= "vicixdev_gfx::Arena"
		info.type	= fmt.tprintf("Gpu memory (%v)", v.memory_type)
		info.used	= memory.end
		info.available	= memory.max - memory.end
		info.start	= 0

	case ^gfx.Scratch:
		info.structure	= "vicixdev_gfx::Scratch"
		info.type	= fmt.tprintf("Gpu memory (%v)", v.memory_type)
		info.used	= memory.end - memory.start
		info.available	= memory.max - info.used
		info.start	= memory.start

	case:
		info.structure	= "Unknown"
		info.type		= "Unknown"
	}

	info.frame_start	= memory.start
	info.end		= memory.end
	info.available		= memory.max
	info.used_this_frame	= memory.end - info.frame_start
	info.percent		= cast(f32)info.used / cast(f32)info.available * 100
	info.percent_this_frame	= cast(f32)info.used_this_frame / cast(f32)info.available * 100

	return
}

// ui_memory_tracker :: proc(ctx: ^ui.Context) {
// 	cnt := ui.get_container(ctx, "Memory tracker")
// 	if cnt != nil && .Just_Pressed in key_states[.M] {
// 		cnt.open = true
// 	}

// 	if ui.window(ctx, "Memory tracker", { 0, 0, 320, 240 }, { .CLOSED }) {
// 		for memory in tl_tracked_memories {
// 			ui.layout_row(ctx, { -1 })
// 			_ui_memory_pool(ctx, memory)
// 		}
// 	}
// }

// _ui_memory_pool :: proc(ctx: ^ui.Context, memory: tl_Tracked_Memory) {

		
// 	ui.layout_row(ctx, { -1 })
// 	if .ACTIVE in ui.header(ctx, memory.label) {
// 		structure, type, available, used, used_this_frame, percent, percent_this_frame, start, frame_start, end := target_type_info(memory)

// 		ui.layout_row(ctx, { -1 }, 20)

// 		ui.label(ctx, fmt.tprintf("Structure: %s", structure))
// 		ui.label(ctx, fmt.tprintf("Type: %s", type))
// 		ui.label(ctx, fmt.tprintf("Available: %d bytes", available))
// 		ui.label(ctx, fmt.tprintf("Used: %d bytes (%.1f%%)", used, percent))
// 		ui.label(ctx, fmt.tprintf("Used this frame: %d bytes (%.1f%%)", used_this_frame, percent_this_frame))

// 		ui.layout_row(ctx, { -1 }, 20)
// 		layout := ui.layout_next(ctx)
// 		current := ui.Rect{ layout.x, layout.y, 0, layout.h }

// 		w0 := cast(i32)((cast(f32)cast(f32)start) / cast(f32)memory.max * cast(f32)layout.w)
// 		w1 := cast(i32)((cast(f32)frame_start - cast(f32)start) / cast(f32)memory.max * cast(f32)layout.w)
// 		w2 := cast(i32)((cast(f32)end - cast(f32)frame_start) / cast(f32)memory.max * cast(f32)layout.w)
// 		w3 := cast(i32)((cast(f32)memory.max - cast(f32)end) / cast(f32)memory.max * cast(f32)layout.w)

// 		current.w = w0
// 		ui.draw_rect(ctx, current, { 125, 125, 125, 255 }); current.x += current.w

// 		current.w = w1
// 		ui.draw_rect(ctx, current, { 100, 25, 25, 255 }); current.x += current.w

// 		current.w = w2
// 		ui.draw_rect(ctx, current, { 255, 255, 0, 255 }); current.x += current.w

// 		current.w = w3
// 		ui.draw_rect(ctx, current, { 100, 100, 100, 255 }); current.x += current.w
// 	}

// }

