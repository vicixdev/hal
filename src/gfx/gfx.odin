package gfx

import "base:runtime"
import "core:mem"
import vmem "core:mem/virtual"
import hm "core:container/handle_map"

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

Target_Api :: enum {
	Metal_3,
	Vulkan,
}

TARGET_API_STRING :: #config(GFX_TARGET_API, "Vulkan")
// TARGET_API_STRING :: #config(GFX_TARGET_API, "Metal_3")
when TARGET_API_STRING == "Vulkan" {
	TARGET_API :: Target_Api.Vulkan
} else when TARGET_API_STRING == "Metal_3" {
	TARGET_API :: Target_Api.Metal_3
} else {
	#panic("Invalid GFX_TARGET_API parameter: expected `Vulkan` or `Metal_3`, got `" + TARGET_API_STRING + "`.")
}

when TARGET_API == .Metal_3 && ODIN_OS != .Darwin {
	#panic(
		"The Metal_3 backend is only available when targeting macOS. Please use the Vulkan backend for other " +
		"platforms.",
	)
}

Error :: enum {
	Not_Initialized,
	Device_Not_Selected,

	Generic_Backend_Error,

	Out_Of_Gpu_Memory,
	Invalid_Align,
	Incompatible_Memory_Type,

	Invalid_Descriptor,
	Invalid_Pipeline_Bytecode,
	Invalid_Pipeline_Constants,

	Invalid_Device,
	Invalid_Buffer,
	Invalid_Texture,
	Invalid_View,
	Invalid_Sampler,
	Invalid_Command_Buffer,
	Invalid_Library,
	Invalid_Pipeline,

	Incompatible_Pipeline,
}

Result :: union {
	runtime.Allocator_Error,
	Error,
}

Handle :: hm.Handle64

Raster_Stage :: enum {
	Vertex,
	Fragment,
	Compute,
}

Stage :: enum {
	Transfer,
	Compute,
	Raster,
}

Stages :: bit_set[Stage]

Command_Buffer :: distinct Handle

_initialized:	bool

Vulkan_Shader_Format :: enum {
	Spirv,
	// When targeting MoltenVK on MacOS, it is possible to directly load Metallib shaders, instead of Spirv ones.
	Metallib,
}

Init_Descriptor :: struct {
	vk:	struct {
		loader_path:	string,
		shader_format:	Vulkan_Shader_Format,
	},
	m3:	struct {},
}

_settings:		Init_Descriptor

_global_arena:		vmem.Arena
_global_allocator:	runtime.Allocator
_temp_scratch:		mem.Scratch
_temp_allocator:	runtime.Allocator

init :: proc(descriptor: Init_Descriptor, location := #caller_location) -> (res: Result) {
	_settings = descriptor

	vmem.arena_init_growing(&_global_arena) or_return
	_global_allocator = vmem.arena_allocator(&_global_arena)

	mem.scratch_init(&_temp_scratch, 32 * mem.Megabyte) or_return
	_temp_allocator = mem.scratch_allocator(&_temp_scratch)

	_init_messaging_system() or_return

	hm.dynamic_init(&_buffers, _global_allocator)
	hm.dynamic_init(&_textures, _global_allocator)
	hm.dynamic_init(&_views, _global_allocator)
	hm.dynamic_init(&_samplers, _global_allocator)
	hm.dynamic_init(&_pipelines, _global_allocator)

	when TARGET_API == .Vulkan {
		res = vk_init()
	} else when TARGET_API == .Metal_3 {
		res = m3_init()
	}

	_check_generic_backend_error(res, location) or_return

	_initialized = true

	return nil
}

fini :: proc() {
	sampler_it := hm.dynamic_iterator_make(&_samplers)
	for _, sampler in hm.iterate(&sampler_it) {
		destroy_sampler(sampler)
	}

	texture_it := hm.dynamic_iterator_make(&_textures)
	for _, texture in hm.iterate(&texture_it) {
		destroy_texture(texture)
	}

	buffer_it := hm.dynamic_iterator_make(&_buffers)
	for _, buffer in hm.iterate(&buffer_it) {
		dealloc({
			handle = buffer,
		})
	}

	when TARGET_API == .Vulkan {
		vk_fini()
	} else when TARGET_API == .Metal_3 {
		m3_fini()
	}

	print_messages()
	_fini_messaging_system()

	vmem.arena_destroy(&_global_arena)
	mem.scratch_destroy(&_temp_scratch)

	_is_device_selected = false
	_device_info = nil
	_initialized = false
}

// create_library_from_bytes :: proc(bytes: []byte) -> (Library, Result) {
// 	switch TARGET_API {
// 	case .Vulkan:
// 		return vk_create_library_from_bytes(bytes)
// 	case .Metal_3:
// 		return m3_create_library_from_bytes(bytes)
// 	case:
// 		return nop_create_library_from_bytes(bytes)
// 	}
// }

// create_library_from_file :: proc(path: string) -> (Library, Result) {
// 	switch TARGET_API {
// 	case .Vulkan:
// 		return vk_create_library_from_file(path)
// 	case .Metal_3:
// 		return m3_create_library_from_file(path)
// 	case:
// 		return nop_create_library_from_file(path)
// 	}
// }

// create_library :: proc {
// 	create_library_from_bytes,
// 	create_library_from_file,
// }

// create_render_pipeline :: proc() -> Pipeline {
// 	switch TARGET_API {
// 	case .Vulkan:
// 		return vk_create_render_pipeline()
// 	case .Metal_3:
// 		panic("Unimplemented.")
// 	case:
// 		return nop_create_render_pipeline()
// 	}
// }

// create_compute_pipeline :: proc(
// 	library: Library,
// 	name: string,
// 	constants: []Constant,
// 	group_size: [3]int,
// ) -> (
// 	Pipeline,
// 	Result,
// ) {
// 	switch TARGET_API {
// 	case .Vulkan:
// 		return vk_create_compute_pipeline(library, name, constants, group_size)
// 	case .Metal_3:
// 		return m3_create_compute_pipeline(library, name, constants, group_size)
// 	case:
// 		return nop_create_compute_pipeline(library, name, constants, group_size)
// 	}
// }

// start_command_encoding :: proc() -> (Command_Buffer, Result) {
// 	switch TARGET_API {
// 	case .Vulkan:
// 		return vk_start_command_encoding()
// 	case .Metal_3:
// 		return m3_start_command_encoding()
// 	case:
// 		return nop_start_command_encoding()
// 	}
// }

// syncronize_buffers :: proc(cb: Command_Buffer) {
// 	switch TARGET_API {
// 	case .Vulkan:
// 		vk_syncronize_buffers(cb)
// 	case .Metal_3:
// 		panic("Unimplemented.")
// 	case:
// 		nop_syncronize_buffers(cb)
// 	}
// }

// mem_copy :: proc(cb: Command_Buffer, destination: Buffer, source: Buffer, size: int) -> Result {
// 	switch TARGET_API {
// 	case .Vulkan:
// 		return vk_mem_copy(cb, destination, source, size)
// 	case .Metal_3:
// 		return m3_mem_copy(cb, destination, source, size)
// 	case:
// 		return nop_mem_copy(cb, destination, source, size)
// 	}
// }

// set_pipeline :: proc(cb: Command_Buffer, pipeline: Pipeline) -> Result {
// 	switch TARGET_API {
// 	case .Vulkan:
// 		return vk_set_pipeline(cb, pipeline)
// 	case .Metal_3:
// 		return m3_set_pipeline(cb, pipeline)
// 	case:
// 		return nop_set_pipeline(cb, pipeline)
// 	}
// }

// set_indirect_buffer_pool :: proc(cb: Command_Buffer, buffers: []Buffer) -> Result {
// 	switch TARGET_API {
// 	case .Vulkan:
// 		return vk_set_indirect_buffer_pool(cb, buffers)
// 	case .Metal_3:
// 		return m3_set_indirect_buffer_pool(cb, buffers)
// 	case:
// 		return nop_set_indirect_buffer_pool(cb, buffers)
// 	}
// }

// set_texture_pool :: proc(cb: Command_Buffer, textures: []View) -> Result {
// 	switch TARGET_API {
// 	case .Vulkan:
// 		return vk_set_texture_pool(cb, textures)
// 	case .Metal_3:
// 		return m3_set_texture_pool(cb, textures)
// 	case:
// 		return nop_set_texture_pool(cb, textures)
// 	}
// }

// set_buffer :: proc(
// 	cb: Command_Buffer,
// 	buffer: Buffer,
// 	index: int,
// 	stage: Raster_Stage = .Compute,
// ) -> Result {
// 	switch TARGET_API {
// 	case .Vulkan:
// 		return vk_set_buffer(cb, buffer, index, stage)
// 	case .Metal_3:
// 		return m3_set_buffer(cb, buffer, index, stage)
// 	case:
// 		return nop_set_buffer(cb, buffer, index, stage)
// 	}
// }

// // copy_buffer_to_texture: proc(cb: Command_Buffer, )
// // copy_texture_to_buffer
// // copy_texture_to_texture
// dispatch :: proc(cb: Command_Buffer, groups: [3]int) -> Result {
// 	switch TARGET_API {
// 	case .Vulkan:
// 		return vk_dispatch(cb, groups)
// 	case .Metal_3:
// 		return m3_dispatch(cb, groups)
// 	case:
// 		return nop_dispatch(cb, groups)
// 	}
// }

// generate_mipmaps :: proc(cb: Command_Buffer, texture: Texture) -> Result {
// 	switch TARGET_API {
// 	case .Vulkan:
// 		return vk_generate_mipmaps(cb, texture)
// 	case .Metal_3:
// 		return m3_generate_mipmaps(cb, texture)
// 	case:
// 		return nop_generate_mipmaps(cb, texture)
// 	}
// }

// begin_renderpass :: proc(
// 	cb: Command_Buffer,
// 	/* ... */
// ) {
// 	switch TARGET_API {
// 	case .Vulkan:
// 		vk_begin_renderpass(cb)
// 	case .Metal_3:
// 		panic("Unimplemented.")
// 	case:
// 		nop_begin_renderpass(cb)
// 	}
// }

// end_renderpass :: proc(cb: Command_Buffer) {
// 	switch TARGET_API {
// 	case .Vulkan:
// 		vk_end_renderpass(cb)
// 	case .Metal_3:
// 		panic("Unimplemented.")
// 	case:
// 		nop_end_renderpass(cb)
// 	}
// }

// draw :: proc(
// 	cb: Command_Buffer,
// 	vertices: int,
// 	instances: int,
// 	vertex_arg: Buffer,
// 	fragment_arg: Buffer,
// 	base_vertex: int,
// ) {
// 	switch TARGET_API {
// 	case .Vulkan:
// 		vk_draw(cb, vertices, instances, vertex_arg, fragment_arg, base_vertex)
// 	case .Metal_3:
// 		panic("Unimplemented.")
// 	case:
// 		nop_draw(cb, vertices, instances, vertex_arg, fragment_arg, base_vertex)
// 	}
// }

// draw_indexed :: proc(
// 	cb: Command_Buffer,
// 	indices: int,
// 	instances: int,
// 	index_buffer: Buffer,
// 	vertex_arg: Buffer,
// 	fragment_arg: Buffer,
// 	base_index: int,
// ) {
// 	switch TARGET_API {
// 	case .Vulkan:
// 		vk_draw_indexed(cb, indices, instances, index_buffer, vertex_arg, fragment_arg, base_index)
// 	case .Metal_3:
// 		panic("Unimplemented.")
// 	case:
// 		nop_draw_indexed(cb, indices, instances, index_buffer, vertex_arg, fragment_arg, base_index)
// 	}
// }

// barrier :: proc(cb: Command_Buffer, before: Stages, after: Stages) -> Result {
// 	switch TARGET_API {
// 	case .Vulkan:
// 		return vk_barrier(cb, before, after)
// 	case .Metal_3:
// 		return m3_barrier(cb, before, after)
// 	case:
// 		return nop_barrier(cb, before, after)
// 	}
// }

// // wait: proc(cb: Command_Buffer)
// // signal: proc(cb: Command_Buffer)

// submit :: proc(cb: Command_Buffer) -> Result {
// 	switch TARGET_API {
// 	case .Vulkan:
// 		return vk_submit(cb)
// 	case .Metal_3:
// 		return m3_submit(cb)
// 	case:
// 		return nop_submit(cb)
// 	}
// }

label :: proc {
	label_buffer,
	label_texture,
	label_view,
	label_sampler,
}

_metadata_of :: proc {
	_buffer_metadata_of,
	_texture_metadata_of,
	_view_metadata_of,
	_sampler_metadata_of,
	_pipeline_metadata_of,
}

_check_initialized :: proc(location: runtime.Source_Code_Location) -> Result {
	_check_condition(
		_initialized,
		.Not_Initialized,
		.Error,
		"Not initialized",
		"The gfx package has not yet been initialized. Please call `gfx::init`.",
		location=location,
	) or_return
	return nil
}

_check_generic_backend_error :: proc(result: Result, location: runtime.Source_Code_Location) -> Result {
	if res, is_alloc_error := result.(runtime.Allocator_Error); is_alloc_error && res != nil {
		_check_result(
			result,
			.Error,
			"Allocation error",
			"The operation failed due to a memory error.",
			location=location,
		) or_return
	} else {
		_check_result(
			result,
			.Error,
			"Generic backend error",
			"The operation failed in an unexpected way.",
			location=location,
		) or_return
	}

	return nil
}

