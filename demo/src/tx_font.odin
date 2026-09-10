package main

import "base:runtime"
import "core:os"
import "core:strings"
import "core:slice"
import "core:math"
import hm "core:container/handle_map"
import ts "vendor:kb_text_shape"
import ttf "vendor:stb/truetype"
import rp "vendor:stb/rect_pack"
import "root:gfx"

tx_FONT_ATLAS_SIZE	:: 4098

// Represents font + size
tx_Font :: distinct hm.Handle64

tx_Glyph_Iterator :: struct {
	font:		tx_Font,
	run:		ts.run,
	position:	[2]f32,
}

tx_Glyph_Draw_Info :: struct {
	dimensions:		[2]f32,
	offset:			[2]f32,

	// Only when iterating glyphs
	advance:		[2]f32,

	atlas_view:		gfx.View,
	atlas_resource_index:	int,
	atlas_position:		[2]int,
	atlas_size:		[2]int,
}

_tx_Font_Key :: struct {
	name:		string,
	height:		f32,
}

_tx_Glyph_Key :: struct {
	glyph:		int,
	shift:		[2]f32,
}

_tx_Font_Atlas :: struct {
	texture:		gfx.Texture,
	view:			gfx.View,
	resource_index:		int,

	pack_context:		^rp.Context,
	nodes:			[]rp.Node,
	glyphs:			[dynamic]_tx_Glyph_Rect,
	staging_atlas:		^[tx_FONT_ATLAS_SIZE * tx_FONT_ATLAS_SIZE]u8,
	was_modified:		bool,
}

_tx_Glyph_Rect :: struct {
	position:		[2]int,
	size:			[2]int,
	offset:			[2]int,

	glyph:			int,
}

_tx_Font_Metadata :: struct {
	handle:			tx_Font,
	root:			int,

	height:			f32,
	scale:			f32,
	
	glyphs:			map[_tx_Glyph_Key]int, // index of `atlas.rects`

	// TODO: make dynamic
	atlas:			_tx_Font_Atlas,
}

// Contains data relative to a ttf font, before specifing the size
_tx_Font_Root :: struct {
	name:			string,

	data:			[]byte,
	font:			ttf.fontinfo,
	ts_font:		^ts.font,
	ts_context:		^ts.shape_context,
}

_tx: struct {
	allocator:		runtime.Allocator,
	ts_allocator:		ts.allocator_function,
	ts_allocator_data:	rawptr,

	private_memory:		^gfx.Arena,
	default_memory:		^gfx.Arena,

	fonts:			hm.Dynamic_Handle_Map(_tx_Font_Metadata, tx_Font),
	registered_fonts:	map[_tx_Font_Key]tx_Font,
	font_roots:		[dynamic]_tx_Font_Root,
	name_lookup:		map[string]int, // index of `font_roots`

	modified_atlases:	[dynamic]^_tx_Font_Atlas,
}

tx_init :: proc(
	private_memory: ^gfx.Arena,
	default_memory: ^gfx.Arena,
	allocator: runtime.Allocator,
) -> Result {

	assert(private_memory.memory_type == .Private)
	assert(default_memory.memory_type == .Default || default_memory.memory_type == .Staging)

	_tx.allocator				= allocator
	_tx.ts_allocator, _tx.ts_allocator_data	= ts.AllocatorFromOdinAllocator(&_tx.allocator)

	_tx.private_memory	= private_memory
	_tx.default_memory	= default_memory

	hm.dynamic_init(&_tx.fonts, allocator)
	_tx.registered_fonts	= make(map[_tx_Font_Key]tx_Font, allocator)
	_tx.font_roots		= make([dynamic]_tx_Font_Root, allocator) or_return
	_tx.name_lookup		= make(map[string]int, allocator)
	_tx.modified_atlases	= make([dynamic]^_tx_Font_Atlas, allocator) or_return

	return nil
}

tx_fini :: proc() {

	font_iter := hm.dynamic_iterator_make(&_tx.fonts)
	for metadata, _ in hm.iterate(&font_iter) {
		free(metadata.atlas.pack_context, _tx.allocator)
		delete(metadata.atlas.glyphs)
		delete(metadata.atlas.nodes, _tx.allocator)
		gfx.destroy_texture(metadata.atlas.texture)

		delete(metadata.glyphs)
	}

	for font_root in _tx.font_roots {
		ts.DestroyShapeContext(font_root.ts_context)
		delete(font_root.data, _tx.allocator)
	}

	hm.dynamic_destroy(&_tx.fonts)
	delete(_tx.registered_fonts)
	delete(_tx.font_roots)
	delete(_tx.name_lookup)
	delete(_tx.modified_atlases)
}

tx_register_font :: proc(path: string, height: f32) -> (font: tx_Font, res: Result) {

	name := _tx_font_name_from_path(path)
	root_id := tx_register_font_root(path) or_return
	
	return tx_instantiate_font(root_id, height)
}

tx_instantiate_font :: proc(root_id: int, height: f32) -> (font: tx_Font, res: Result) {

	if root_id >= len(_tx.font_roots) {
		return {}, .Invalid_Handle
	}

	height := _tx_quantize(height, 4)

	root := &_tx.font_roots[root_id]

	is_already_present: bool
	font, is_already_present = _tx.registered_fonts[{ root.name, height }]
	if is_already_present {
		return font, .Exists_Already
	}

	scale := ttf.ScaleForPixelHeight(&root.font, height)

	metadata := _tx_Font_Metadata {
		root	= root_id,
		height	= height,
		scale	= scale,
		glyphs	= make(map[_tx_Glyph_Key]int, _tx.allocator),
	}
	_tx_init_font_atlas(&metadata.atlas, _tx.private_memory, _tx.default_memory, _tx.allocator) or_return

	font = hm.add(&_tx.fonts, metadata) or_return
	map_insert(&_tx.registered_fonts, _tx_Font_Key { root.name, height }, font)
	
	return
}

tx_use_rune :: tx_use_codepoint
tx_use_codepoint :: proc(font: tx_Font, codepoint: rune, shift: [2]f32 = {}) -> (draw_info: tx_Glyph_Draw_Info, res: Result) {

	metadata, font_root := _tx_metadata_of(font) or_return
	
	glyph := cast(int)ttf.FindGlyphIndex(&font_root.font, codepoint)

	draw_info, _, res = _tx_use_glyph(metadata, &font_root.font, cast(int)glyph, shift)
	return
}

tx_register_font_root :: proc(path: string) -> (root_id: int, res: Result) {

	font_name := _tx_font_name_from_path(path)

	already_registered: bool
	root_id, already_registered = _tx.name_lookup[font_name]
	if already_registered {
		return root_id, nil
	}

	font_root := _tx_Font_Root {
		name	= font_name,
	}

	font_root.data = os.read_entire_file(path, _tx.allocator) or_return
	font_ok := ttf.InitFont(&font_root.font, raw_data(font_root.data), 0)
	if !font_ok {
		// TODO: Make font 0 a well known debug font
		return 0, .Could_Not_Parse_File
	}

	font_root.ts_context = ts.CreateShapeContext2(_tx.ts_allocator, _tx.ts_allocator_data, {})
	font_root.ts_font = ts.ShapePushFontFromMemory(font_root.ts_context, font_root.data, 0)

	root_id = len(_tx.font_roots)
	append(&_tx.font_roots, font_root)
	map_insert(&_tx.name_lookup, font_name, root_id)

	return root_id, nil
}

tx_sync_font_textures :: proc(command_buffer: gfx.Command_Buffer) -> (res: gfx.Result) {

	for &atlas in _tx.modified_atlases {
		sync_res := _tx_sync_font_atlas(command_buffer, atlas)
		if sync_res != nil {
			res = sync_res
		}
	}

	resize(&_tx.modified_atlases, 0)

	return res
}

tx_make_glyph_iterator :: proc(
	font: tx_Font,
	str: string,
	staring_position: [2]f32,
) -> (iterator: tx_Glyph_Iterator, res: Result) {
	
	metadata, font_root := _tx_metadata_of(font) or_return

	ts.ShapeBegin(font_root.ts_context, .DONT_KNOW, .DONT_KNOW)
		ts.ShapePushFeature(font_root.ts_context, .kern, 0)
		ts.ShapeUtf8(font_root.ts_context, str, .SOURCE_INDEX)
		_ = ts.ShapePopFeature(font_root.ts_context, .kern)
	ts.ShapeEnd(font_root.ts_context)

	run_ok: b32
	iterator.run, run_ok = ts.ShapeRun(font_root.ts_context)
	if !run_ok {
		return {}, .Generic_Error
	}

	ascent, descent, line_gap: i32
	ttf.GetFontVMetrics(&font_root.font, &ascent, &descent, &line_gap)

	iterator.font		= font
	iterator.position	= {
		staring_position.x,
		staring_position.y + cast(f32)descent * metadata.scale,
	}

	return
}

tx_iterate_glyph :: proc(iterator: ^tx_Glyph_Iterator) -> (
	_draw_info:	tx_Glyph_Draw_Info,
	cursor:		[2]f32,
	ok:		bool,
) {
	
	metadata, font_root, metadata_res := _tx_metadata_of(iterator.font)
	if metadata_res != nil {
		return {}, {}, false
	}

	glyph_info, glyph_ok := ts.GlyphIteratorNext(&iterator.run.Glyphs)
	if !glyph_ok {
		return {}, {}, false
	}

	cursor = iterator.position
	shift := [2]f32 {
		math.remainder(cursor.x, 1.0),
		math.remainder(cursor.y, 1.0),
	}

	draw_info, glyph_rect, glyph_res := _tx_use_glyph(metadata, &font_root.font, cast(int)glyph_info.Id)
	if glyph_res != nil {
		return {}, {}, false
	}

	draw_info.advance = {
		cast(f32)glyph_info.AdvanceX * metadata.scale,
		cast(f32)glyph_info.AdvanceY * metadata.scale,
	}
	draw_info.offset += {
		cast(f32)glyph_info.OffsetX * metadata.scale,
		cast(f32)glyph_info.OffsetY * metadata.scale,
	}

	iterator.position += draw_info.advance

	return draw_info, cursor, true
}

tx_dimensions_of :: proc(font: tx_Font, str: string) -> (dimensions: [2]f32, res: Result) {
	
	iterator := tx_make_glyph_iterator(font, str, {}) or_return

	cursor: f32
	for draw_info in tx_iterate_glyph(&iterator) {
		cursor += draw_info.advance.x

		dimensions.x = max(dimensions.x, cursor)
	}

	metadata, root := _tx_metadata_of(font) or_return

	ascent, descent, line_gap: i32
	ttf.GetFontVMetrics(&root.font, &ascent, &descent, &line_gap)

	dimensions.y = cast(f32)(ascent - descent) * metadata.scale

	return
}

// NOTE: root is not pointer-stable
_tx_metadata_of :: proc(font: tx_Font) -> (metadata: ^_tx_Font_Metadata, root: ^_tx_Font_Root, res: Result) {
	metadata_ok: bool
	metadata, metadata_ok = hm.get(&_tx.fonts, font)
	if !metadata_ok {
		return nil, nil, .Invalid_Handle
	}

	root = &_tx.font_roots[metadata.root]

	return
}

_tx_use_glyph :: proc(
	metadata:	^_tx_Font_Metadata,
	font:		^ttf.fontinfo,
	glyph:		int,
	shift:		[2]f32 = {},
) -> (draw_info: tx_Glyph_Draw_Info, glyph_rect: _tx_Glyph_Rect, res: Result) {

	normalized_shift := [2]f32 {
		_tx_quantize(shift.x, 4),
		_tx_quantize(shift.y, 4),
	}

	glyph_idx, already_registered := metadata.glyphs[{glyph, shift}]
	if !already_registered {
		if !metadata.atlas.was_modified {
			append(&_tx.modified_atlases, &metadata.atlas)
		}

		glyph_idx = _tx_add_glyph_to(&metadata.atlas, font, metadata.scale, glyph, normalized_shift) or_return
		map_insert(&metadata.glyphs, _tx_Glyph_Key{ glyph, shift }, glyph_idx)
	}

	glyph_rect = metadata.atlas.glyphs[glyph_idx]

	draw_info.offset		= {
		cast(f32)glyph_rect.offset.x,
		cast(f32)glyph_rect.offset.y,
	}
	draw_info.dimensions		= {
		cast(f32)glyph_rect.size.x,
		cast(f32)glyph_rect.size.y,
	}
	draw_info.atlas_view		= metadata.atlas.view
	draw_info.atlas_resource_index	= metadata.atlas.resource_index
	draw_info.atlas_position	= glyph_rect.position
	draw_info.atlas_size		= glyph_rect.size
	return
}

_tx_init_font_atlas :: proc(
	atlas:	^_tx_Font_Atlas,
	private_arena:	^gfx.Arena,
	default_arena:	^gfx.Arena,
	allocator:	runtime.Allocator,
) -> Result {
	
	assert(private_arena.memory_type == .Private)
	assert(default_arena.memory_type == .Default || default_arena.memory_type == .Staging)

	texture_descriptor := gfx.Texture_Descriptor {
		type		= .D2_Array,
		dimensions	= { tx_FONT_ATLAS_SIZE, tx_FONT_ATLAS_SIZE, 1 },
		format		= .R8_Unorm,
		usage		= { .Sampled },
	}
	texture_size, texture_align := gfx.size_align_of(texture_descriptor) or_return
	texture_memory := gfx.arena_alloc(private_arena, texture_size, texture_align) or_return
	atlas.texture = gfx.create_texture(texture_memory, texture_descriptor) or_return
	atlas.view = gfx.default_view_of(atlas.texture) or_return

	resource_manager := rd_resource_manager()
	atlas.resource_index = rd_acquire_resource_id(resource_manager, gfx.View_Type.D2, atlas.view)

	atlas.staging_atlas = gfx.arena_alloc(default_arena, [tx_FONT_ATLAS_SIZE * tx_FONT_ATLAS_SIZE]u8) or_return

	atlas.nodes	= make([]rp.Node, tx_FONT_ATLAS_SIZE, allocator) or_return
	atlas.glyphs	= make([dynamic]_tx_Glyph_Rect, allocator) or_return
	atlas.pack_context = new(rp.Context, allocator)
	rp.init_target(
		atlas.pack_context,
		tx_FONT_ATLAS_SIZE,
		tx_FONT_ATLAS_SIZE,
		&atlas.nodes[0],
		cast(i32)len(atlas.nodes),
	)

	return nil
}

_tx_sync_font_atlas :: proc(
	command_buffer:	gfx.Command_Buffer,
	atlas:		^_tx_Font_Atlas,
) -> gfx.Result {

	region := gfx.Texture_Region {
		layer_count	= 1,
		size		= { tx_FONT_ATLAS_SIZE, tx_FONT_ATLAS_SIZE, 1 },
	}
	gfx.copy_buffer_to_texture(
		command_buffer,
		atlas.staging_atlas,
		atlas.texture,
		region,
	) or_return

	atlas.was_modified = false

	return nil
}

_tx_add_glyph_to :: proc(
	atlas:		^_tx_Font_Atlas,
	font:		^ttf.fontinfo,
	scale:		f32,
	glyph:		int,
	shift:		[2]f32 = {}
) -> (glyph_idx: int, res: Result) {

	BORDER		:: 4
	BORDER_HALF	:: BORDER / 2

	PADDING		:: 4
	ONEGDE		:: 128
	PIXEL_DIST	:: 32

	width, height: i32
	xoff, yoff: i32
	glyph_bitmap := ttf.GetGlyphBitmapSubpixel(
		font,
		scale,
		scale,
		shift.x,
		shift.y,
		cast(i32)glyph,
		&width,
		&height,
		&xoff,
		&yoff,
	)
	defer ttf.FreeBitmap(glyph_bitmap, nil)

	rect := rp.Rect {
		id	= cast(i32)glyph,
		w	= cast(rp.Coord)width + BORDER,
		h	= cast(rp.Coord)height + BORDER,
	}

	if rp.pack_rects(atlas.pack_context, &rect, 1) == 0 {
		return 0, .Out_Of_Atlas_Space
	}

	// Totally unoptimied cpu copy :-)
	for y in 0..<height do for x in 0..<width {
		src_x := x
		src_y := y
		src_idx := src_y * width + src_x

		dest_x := cast(i32)rect.x + x + BORDER_HALF
		dest_y := cast(i32)rect.y + y + BORDER_HALF
		dest_idx := dest_y * tx_FONT_ATLAS_SIZE + dest_x

		atlas.staging_atlas[dest_idx] = glyph_bitmap[src_idx]
	}

	glyph_rect := _tx_Glyph_Rect {
		glyph		= glyph,
		position	= {
			cast(int)rect.x + BORDER_HALF, cast(int)rect.y + BORDER_HALF,
		},
		size		= {
			cast(int)width, cast(int)height,
		},
		offset		= {
			cast(int)xoff, cast(int)yoff,
		},
	}

	glyph_idx = len(atlas.glyphs)
	append(&atlas.glyphs, glyph_rect)

	atlas.was_modified = true

	return glyph_idx, nil
}

_tx_font_name_from_path :: proc(path: string) -> string {
	splits := strings.split(path, "/", context.temp_allocator)
	return slice.last(splits)
}

// Normalizes the shift into the nearest discrete levels
// Es f(0.6, 4) = 0.5, f(0.15) = 0.25
_tx_quantize :: proc(shift: f32, subpixel_levels: f32) -> f32 {
	return math.round(shift * subpixel_levels) / subpixel_levels
}

