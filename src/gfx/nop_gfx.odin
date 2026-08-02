package gfx

nop_init :: proc() {}
nop_fini :: proc() {}

nop_alloc :: proc(type: Memory, size: int) -> (handle: Buffer, res: Result) {
	return
}
nop_dealloc :: proc(buffer: Buffer) {
	return
}
nop_gpu_reference_of :: proc(buffer: Buffer) -> (ref: uintptr, res: Result) {
	return
}
nop_mark_as_modified :: proc(buffer: Buffer, length: int) {}
nop_label_buffer :: proc(buffer: Buffer, label: string) {}

nop_size_align_of :: proc(descriptor: Texture_Descriptor) -> (size: int, align: int, res: Result) {
	return
}
nop_create_texture :: proc(
	buffer: Buffer,
	descriptor: Texture_Descriptor,
) -> (
	handle: Texture,
	res: Result,
) {
	return
}
nop_destroy_texture :: proc(texture: Texture) {}
nop_label_texture :: proc(texture: Texture, label: string) {}

nop_create_default_view :: proc(texture: Texture) -> (handle: View, res: Result) {
	return
}
nop_create_view_with_descriptor :: proc(
	texture: Texture,
	descriptor: View_Descriptor,
) -> (
	handle: View,
	res: Result,
) {
	return
}
nop_label_view :: proc(view: View, label: string) {}

nop_create_library_from_bytes :: proc(bytes: []byte) -> (handle: Library, res: Result) {
	return
}
nop_create_library_from_file :: proc(path: string) -> (handle: Library, res: Result) {
	return
}

nop_create_compute_pipeline :: proc(
	library: Library,
	name: string,
	constants: []Constant,
	group_size: [3]int,
) -> (
	handle: Pipeline,
	res: Result,
) {
	return
}
nop_create_render_pipeline :: proc() -> (handle: Pipeline) {
	return
}

nop_start_command_encoding :: proc() -> (handle: Command_Buffer, res: Result) {
	return
}

nop_syncronize_buffers :: proc(cb: Command_Buffer) {}
nop_mem_copy :: proc(cb: Command_Buffer, destination: Buffer, source: Buffer, size: int) -> Result {
	return nil
}

nop_set_pipeline :: proc(cb: Command_Buffer, pipeline: Pipeline) -> Result {
	return nil
}
nop_set_indirect_buffer_pool :: proc(cb: Command_Buffer, buffers: []Buffer) -> Result {
	return nil
}
nop_set_texture_pool :: proc(cb: Command_Buffer, textures: []View) -> Result {
	return nil
}
nop_set_buffer :: proc(
	cb: Command_Buffer,
	buffer: Buffer,
	index: int,
	stage: Raster_Stage = .Compute,
) -> Result {
	return nil
}

// copy_buffer_to_texture: proc(cb: Command_Buffer, )
// copy_texture_to_buffer
// copy_texture_to_texture
nop_dispatch :: proc(cb: Command_Buffer, groups: [3]int) -> Result {
	return nil
}

nop_generate_mipmaps :: proc(cb: Command_Buffer, texture: Texture) -> Result {
	return nil
}

nop_begin_renderpass :: proc(
	cb: Command_Buffer,
	/* ... */
) {}
nop_end_renderpass :: proc(cb: Command_Buffer) {}
nop_draw :: proc(
	cb: Command_Buffer,
	vertices: int,
	instances: int,
	vertex_arg: Buffer,
	fragment_arg: Buffer,
	base_vertex: int,
) {}
nop_draw_indexed :: proc(
	cb: Command_Buffer,
	indices: int,
	instances: int,
	index_buffer: Buffer,
	vertex_arg: Buffer,
	fragment_arg: Buffer,
	base_index: int,
) {}

nop_barrier :: proc(cb: Command_Buffer, before: Stages, after: Stages) -> Result {
	return nil
}
// wait: proc(cb: Command_Buffer)
// signal: proc(cb: Command_Buffer)

nop_submit :: proc(cb: Command_Buffer) -> Result {
	return nil
}

