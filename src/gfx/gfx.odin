package gfx

import "base:runtime"
import hm "core:container/handle_map"
import "core:log"
import "core:mem"

// Features:
//	- Vertex pooling (no explicit layout)
//	- Bindless resources
//	- Parallel execution
//	- In flight frames
//	- First-party suballocations and custom allocators
//
// Target HW:
//	- Metal 3 for Apple silicon (UMA)
//	- Vulkan 1.3, any memory architecture


Error :: enum {
	Out_Of_Gpu_Memory,
	Invalid_Buffer,
	Invalid_Texture,
	Invalid_View,
	Invalid_Command_Buffer,
	Invalid_Library,
	Invalid_Pipeline,
	Incompatible_Pipeline,
}

Result :: union #shared_nil {
	runtime.Allocator_Error,
	Error,
}

Handle :: hm.Handle64

Memory :: enum {
	Default,
	Private,
	Readback,
}

GpuDataRef :: uintptr

Raster_Stage :: enum {
	Vertex,
	Fragment,
	Compute,
}

Texture_Type :: enum {
	D1,
	D2,
	D3,
	CUBE,
	D2_ARRAY,
	CUBE_ARRAY,
}

Pixel_Format :: enum {
	NONE,
	R8_Unorm,
	RG8_Unorm,
	RGBA8_Unorm,
	RGBA8_Srgb,
	BGRA8_Unorm,
	BGRA8_Srgb,
	R16_Float,
	RG16_Float,
	RGBA16_Float,
	RGBA16_Unorm,
	R16_Unorm,
	RG16_Unorm,
	R32_Float,
	RG32_Float,
	RGBA32_Float,
	RG11B10_Float,
	RGB10_A2_Unorm,
	RGB10_A2_Uint,
	D32_Float,
	D24_Unorm_S8_Uint,
	D32_Float_S8_Uint,
	D16_Unorm,
}

Texture_Usage :: enum {
	Sampled = 0,
	Storage,
	Color_attachment,
	Depth_stencil_attachment,
}

Texture_Descriptor :: struct {
	type:         Texture_Type,
	dimensions:   [3]int,
	mip_count:    int,
	layer_count:  int,
	sample_count: int,
	format:       Pixel_Format,
	usage:        Texture_Usage,
}

Texture_Channel_Swizzle :: enum {
	Identity,
	Zero,
	One,
	R,
	G,
	B,
	Alpha,
}

Texture_Swizzle :: struct {
	r, g, b, a: Texture_Channel_Swizzle,
}

View_Descriptor :: struct {
	format:      Pixel_Format,
	base_mip:    int,
	mip_count:   int,
	base_layer:  int,
	layer_count: int,
	swizzle:     Texture_Swizzle,
}

Stage :: enum {
	Transfer,
	Compute,
	Raster,
}

Stages :: bit_set[Stage]

Buffer :: struct {
	handle:  Handle,
	using _: struct #raw_union {
		// If the memory type is `Default` or `Readback` it contains the Cpu Mapped Virtual Address.
		contents:  rawptr,
		// If the memory type is `Private` contains a gpu-decodable reference to a buffer + offset into it.
		//	Depending on the implementation, if device pointer are supported, it is the Gpu Virtual Address,
		//	otherwise it is a handle that will require decoding on the GPU side.
		reference: GpuDataRef,
	},
}

Texture :: distinct Handle
View :: distinct Handle
Command_Buffer :: distinct Handle
Library :: distinct Handle
Pipeline :: distinct Handle

Constant_Type :: enum {
	U32,
	F32,
}

Constant :: struct {
	index: int,
	value: rawptr,
	type:  Constant_Type,
}

init: proc() : _init
fini: proc() : _fini

alloc :: proc(type: Memory, size: int) -> (Buffer, Result) {
	if size <= 16 * mem.Kilobyte {
		log.warnf(
			"Small GPU allocation detected (%d bytes). The gfx::alloc procedure should be used to " +
			"allocate big buffers (>= 16 kilobytes), which should be suballocated by the application " +
			"using custom allocators.",
			size,
		)
	}

	return _alloc(type, size)
}

dealloc :: proc(buffer: Buffer) {
	_dealloc(buffer)
}

gpu_reference_of :: proc(buffer: Buffer) -> (GpuDataRef, Result) {
	return _gpu_reference_of(buffer)
}

mark_as_modified :: proc(buffer: Buffer, length: int) {
	_mark_as_modified(buffer, length)
}

label_buffer :: proc(buffer: Buffer, label: string) {
	_label_buffer(buffer, label)
}

size_align_of: proc(descriptor: Texture_Descriptor) -> (size: int, align: int, res: Result) :
	_size_align_of
create_texture: proc(
		buffer: Buffer,
		descriptor: Texture_Descriptor,
	) -> (
		handle: Texture,
		res: Result,
	) :
	_create_texture
destroy_texture: proc(texture: Texture) : _destroy_texture
label_texture: proc(texture: Texture, label: string) : _label_texture

create_default_view: proc(texture: Texture) -> (View, Result) : _create_default_view
create_view_with_descriptor: proc(
		texture: Texture,
		descriptor: View_Descriptor,
	) -> (
		View,
		Result,
	) :
	_create_view_with_descriptor
create_view :: proc {
	create_default_view,
	create_view_with_descriptor,
}
label_view: proc(view: View, label: string) : _label_view

create_library_from_bytes: proc(bytes: []byte) -> (Library, Result) : _create_library_from_bytes
create_library_from_file: proc(path: string) -> (Library, Result) : _create_library_from_file
create_library :: proc {
	create_library_from_bytes,
	create_library_from_file,
}

create_compute_pipeline: proc(
	library: Library,
	name: string,
	constants: []Constant,
	group_size: [3]int,
) -> (
	Pipeline,
	Result,
)
create_render_pipeline: proc() -> Pipeline

start_command_encoding: proc() -> (Command_Buffer, Result) : _start_command_encoding

syncronize_buffers: proc(cb: Command_Buffer)
mem_copy: proc(cb: Command_Buffer, destination: Buffer, source: Buffer, size: int) -> Result :
	_mem_copy

set_pipeline: proc(cb: Command_Buffer, pipeline: Pipeline) -> Result
set_indirect_buffer_pool: proc(cb: Command_Buffer, buffers: []Buffer) -> Result
set_texture_pool: proc(cb: Command_Buffer, textures: []View) -> Result
set_buffer: proc(
	cb: Command_Buffer,
	buffer: Buffer,
	index: int,
	stage: Raster_Stage = .Compute,
) -> Result

// copy_buffer_to_texture: proc(cb: Command_Buffer, )
// copy_texture_to_buffer
// copy_texture_to_texture
dispatch: proc(cb: Command_Buffer, groups: [3]int) -> Result

generate_mipmaps: proc(cb: Command_Buffer, texture: Texture) -> Result : _generate_mipmaps

begin_renderpass: proc(
	cb: Command_Buffer,
	/* ... */
)
end_renderpass: proc(cb: Command_Buffer)
draw: proc(
	cb: Command_Buffer,
	vertices: int,
	instances: int,
	vertex_arg: Buffer,
	fragment_arg: Buffer,
	base_vertex: int,
)
draw_indexed: proc(
	cb: Command_Buffer,
	indices: int,
	instances: int,
	index_buffer: Buffer,
	vertex_arg: Buffer,
	fragment_arg: Buffer,
	base_index: int,
)

barrier: proc(cb: Command_Buffer, before: Stages, after: Stages) -> Result : _barrier
// wait: proc(cb: Command_Buffer)
// signal: proc(cb: Command_Buffer)

submit: proc(cb: Command_Buffer) -> Result : _submit

label :: proc {
	label_buffer,
	label_texture,
	label_view,
}

