package main

import "core:mem"
import "core:fmt"
import vmem "core:mem/virtual"
import ui "vendor:microui"
import "gfx"

tl_Tracked_Memory_Target :: union #no_nil {
	^mem.Arena,
	^mem.Scratch,
	^vmem.Arena,
	^gfx.Arena,
	^gfx.Scratch,
}

tl_Tracked_Memory :: struct {
	label:	string,
	target:	tl_Tracked_Memory_Target,
}

tl_tracked_memories:	[dynamic]tl_Tracked_Memory

tl_track_memory :: proc(label: string, target: tl_Tracked_Memory_Target) {
	append(&tl_tracked_memories, tl_Tracked_Memory {
		label	= label,
		target	= target,
	})
}

tl_track_internal_gfx_memory :: proc() {
	tl_track_memory("gfx::_global_arena",	&gfx._global_arena)
	tl_track_memory("gfx::_temp_scratch",	&gfx._temp_scratch)

	for &command_buffer, i in gfx._command_buffers[.Default] {
		label := fmt.aprintf("gfx::_command_buffers[.Default][%v]", i)
		tl_track_memory(label, &command_buffer.arena)
	}
	if gfx._device_info.properties.transfer_queue {
		for &command_buffer, i in gfx._command_buffers[.Transfer] {
			label := fmt.aprintf("gfx::_command_buffers[.Transfer][%v]", i)
			tl_track_memory(label, &command_buffer.arena)
		}
	}
}

ui_memory_tracker :: proc(ctx: ^ui.Context) {
	if ui.window(ctx, "Memory tracker", { 0, 0, 640, 480 }, { .NO_CLOSE }) {
		for memory in tl_tracked_memories {
			ui.layout_row(ctx, { -1 })
			switch v in memory.target {
			case ^mem.Arena:
				_ui_memory_pool(ctx, memory.label, 0, v.offset, len(v.data))

			case ^mem.Scratch:
				_ui_memory_pool(ctx, memory.label, 0, v.curr_offset, len(v.data))

			case ^vmem.Arena:
				_ui_memory_pool(ctx, memory.label, 0, cast(int)v.total_used, cast(int)v.total_reserved)

			case ^gfx.Arena:
				_ui_memory_pool(ctx, memory.label, 0, v.offset, v.size)

			case ^gfx.Scratch:
				_ui_memory_pool(ctx, memory.label, 0, v.offset, v.size)
			}
		}
	}
}

_ui_memory_pool :: proc(ctx: ^ui.Context, name: string, begin: int, end: int, max: int) {
	ui.layout_row(ctx, { 250, -1 }, 20)

	ui.label(ctx, name)

	ui.layout_begin_column(ctx)
	ui.layout_row(ctx, { -1 }, 20)
		layout := ui.layout_next(ctx)
		current := ui.Rect{ layout.x, layout.y, 0, layout.h }

		w1 := cast(i32)(cast(f32)begin / cast(f32)max * cast(f32)layout.w)
		w2 := cast(i32)((cast(f32)end - cast(f32)begin) / cast(f32)max * cast(f32)layout.w)
		w3 := cast(i32)((cast(f32)max - cast(f32)end) / cast(f32)max * cast(f32)layout.w)

		current.w = w1
		ui.draw_rect(ctx, current, { 25, 25, 25, 255 }); current.x += current.w

		current.w = w2
		ui.draw_rect(ctx, current, { 255, 255, 0, 255 }); current.x += current.w

		current.w = w3
		ui.draw_rect(ctx, current, { 100, 100, 100, 255 }); current.x += current.w
	ui.layout_end_column(ctx)
}

