#+build !linux
#+build !darwin
package gfx

_init :: proc() {}
_fini :: proc() {}

_alloc :: proc(type: Memory, size: int) -> (handle: Buffer, res: Result) {
	return
}
_dealloc :: proc(buffer: Buffer) {
	return
}
_gpu_reference_of :: proc(buffer: Buffer) -> (ref: GpuDataRef, res: Result) {
	return
}
_mark_as_modified :: proc(buffer: Buffer, length: int) {}
_label_buffer :: proc(buffer: Buffer, label: string) {}

_size_align_of :: proc(descriptor: Texture_Descriptor) -> (size: int, align: int, res: Result) {
	return
}
_create_texture :: proc(
	buffer: Buffer,
	descriptor: Texture_Descriptor,
) -> (
	handle: Texture,
	res: Result,
) {
	return
}
_destroy_texture :: proc(texture: Texture) {}
_label_texture :: proc(texture: Texture, label: string) {}

_create_default_view :: proc(texture: Texture) -> (handle: View, res: Result) {
	return
}
_create_view_with_descriptor :: proc(
	texture: Texture,
	descriptor: View_Descriptor,
) -> (
	handle: View,
	res: Result,
) {
	return
}
_label_view :: proc(view: View, label: string) {}

_create_library_from_bytes :: proc(bytes: []byte) -> (handle: Library, res: Result) {
	return
}
_create_library_from_file :: proc(path: string) -> (handle: Library, res: Result) {
	return
}

_create_compute_pipeline :: proc(
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
_create_render_pipeline :: proc() -> (handle: Pipeline) {
	return
}

_start_command_encoding :: proc() -> (handle: Command_Buffer, res: Result) {
	return
}

_syncronize_buffers :: proc(cb: Command_Buffer) {}
_mem_copy :: proc(cb: Command_Buffer, destination: Buffer, source: Buffer, size: int) -> Result {
	return nil
}

_set_pipeline :: proc(cb: Command_Buffer, pipeline: Pipeline) -> Result {
	return nil
}
_set_indirect_buffer_pool :: proc(cb: Command_Buffer, buffers: []Buffer) -> Result {
	return nil
}
_set_texture_pool :: proc(cb: Command_Buffer, textures: []View) -> Result {
	return nil
}
_set_buffer :: proc(
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
_dispatch :: proc(cb: Command_Buffer, groups: [3]int) -> Result {
	return nil
}

_generate_mipmaps :: proc(cb: Command_Buffer, texture: Texture) -> Result {
	return nil
}

_begin_renderpass :: proc(
	cb: Command_Buffer,
	/* ... */
) {}
_end_renderpass :: proc(cb: Command_Buffer) {}
_draw :: proc(
	cb: Command_Buffer,
	vertices: int,
	instances: int,
	vertex_arg: Buffer,
	fragment_arg: Buffer,
	base_vertex: int,
) {}
_draw_indexed :: proc(
	cb: Command_Buffer,
	indices: int,
	instances: int,
	index_buffer: Buffer,
	vertex_arg: Buffer,
	fragment_arg: Buffer,
	base_index: int,
) {}

_barrier :: proc(cb: Command_Buffer, before: Stages, after: Stages) -> Result {
	return nil
}
// wait: proc(cb: Command_Buffer)
// signal: proc(cb: Command_Buffer)

_submit :: proc(cb: Command_Buffer) -> Result {
	return nil
}

