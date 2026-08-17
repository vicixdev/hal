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

// TARGET_API_STRING :: #config(GFX_TARGET_API, "Vulkan")
// TARGET_API_STRING :: #config(GFX_TARGET_API, "Metal_3")
TARGET_API_STRING :: #config(GFX_TARGET_API, "")
when TARGET_API_STRING == "Vulkan" {
	TARGET_API :: Target_Api.Vulkan
} else when TARGET_API_STRING == "Metal_3" {
	TARGET_API :: Target_Api.Metal_3
} else when TARGET_API_STRING == "" {
	when ODIN_OS == .Darwin {
		TARGET_API :: Target_Api.Metal_3
	} else {
		TARGET_API :: Target_Api.Vulkan
	}
} else {
	#panic("Invalid GFX_TARGET_API parameter: expected `Vulkan` or `Metal_3`, got `" + TARGET_API_STRING + "`.")
}

when TARGET_API == .Metal_3 && ODIN_OS != .Darwin {
	#panic(
		"The Metal_3 backend is only available when targeting macOS. Please use the Vulkan backend for other " +
		"platforms.",
	)
}

ENABLE_VALIDATION	:: #config(GFX_ENABLE_VALIDATION, false)
// ENABLE_VALIDATION	:: #config(GFX_ENABLE_VALIDATION, true)
ENABLE_TRACING		:: #config(GFX_ENABLE_TRACING, false)

Error :: enum {
	Not_Initialized,
	Device_Not_Selected,

	Generic_Backend_Error,

	Out_Of_Gpu_Memory,
	Invalid_Align,
	Incompatible_Memory_Type,
	Invalid_Pipeline_Argument,
	Out_Of_Bounds,

	Invalid_Descriptor,
	Invalid_Arguments,
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
	Invalid_Queue,
	Invalid_Resource_Set,
	Invalid_Semaphore,
	Invalid_Fence,

	No_Available_Command_Buffers,
	Incompatible_Pipeline,
	Use_After_Free,
}

Result :: union #shared_nil {
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

// Command_Buffer :: distinct Handle

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
_initialized:		bool

_global_arena:		vmem.Arena
_global_allocator:	runtime.Allocator
_temp_scratch:		mem.Scratch
_temp_allocator:	runtime.Allocator
_generic_allocator:	runtime.Allocator

init :: proc(descriptor := Init_Descriptor{}, location := #caller_location) -> (res: Result) {
	_settings = descriptor

	vmem.arena_init_growing(&_global_arena) or_return
	_global_allocator = vmem.arena_allocator(&_global_arena)

	mem.scratch_init(&_temp_scratch, 128 * mem.Megabyte) or_return
	_temp_allocator = mem.scratch_allocator(&_temp_scratch)

	_generic_allocator = context.allocator

	hm.dynamic_init(&_buffers, _global_allocator)
	hm.dynamic_init(&_textures, _global_allocator)
	hm.dynamic_init(&_views, _global_allocator)
	hm.dynamic_init(&_samplers, _global_allocator)
	hm.dynamic_init(&_pipelines, _global_allocator)
	hm.dynamic_init(&_resource_sets, _global_allocator)
	hm.dynamic_init(&_semaphores, _global_allocator)
	hm.dynamic_init(&_fences, _global_allocator)

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
	if _is_device_selected {
		destroy_resource_set(_default_resource_set)
	}

	when TARGET_API == .Vulkan {
		vk_pre_fini()
	} else when TARGET_API == .Metal_3 {
		m3_pre_fini()
	}

	fence_it := hm.dynamic_iterator_make(&_fences)
	for _, fence in hm.iterate(&fence_it) {
		destroy_fence(fence)
	}

	semaphore_it := hm.dynamic_iterator_make(&_semaphores)
	for _, semaphore in hm.iterate(&semaphore_it) {
		destroy_semaphore(semaphore)
	}

	resource_set_it := hm.dynamic_iterator_make(&_resource_sets)
	for _, resource_set in hm.iterate(&resource_set_it) {
		destroy_resource_set(resource_set)
	}

	pipelines_it := hm.dynamic_iterator_make(&_pipelines)
	for _, pipeline in hm.iterate(&pipelines_it) {
		destroy_pipeline(pipeline)
	}

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

	vmem.arena_destroy(&_global_arena)
	mem.scratch_destroy(&_temp_scratch)

	_is_device_selected = false
	_device_info = nil
	_initialized = false
}

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
	_queue_metadata_of,
	_command_buffer_metadata_of,
	_resource_set_metadata_of,
	_semaphore_metadata_of,
	_fence_metadata_of,
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

