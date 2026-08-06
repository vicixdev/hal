package gfx

import "base:runtime"
import "core:os"
import "core:strings"
import hm "core:container/handle_map"

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

Shader_Stage_Descriptor :: struct {
	bytecode:	[]byte,
	entrypoint:	string,
	constants:	[]Constant,
}

_Pipeline_Type :: enum {
	Compute,
	Render,
}

_Pipeline_Metadata :: struct {
	handle:	Pipeline,
	type:	_Pipeline_Type,

	using type_metadata: struct #raw_union {
		compute:	struct {
			using desc:	Shader_Stage_Descriptor,
		},
		render:		struct {
			vertex:		Shader_Stage_Descriptor,
			fragment:	Shader_Stage_Descriptor,
		},
	},

	using platform: struct #raw_union {
		vk:	vk_Pipeline_Metadata,
		m3:	m3_Pipeline_Metadata,
	},
}

_pipelines: hm.Dynamic_Handle_Map(_Pipeline_Metadata, Pipeline)

create_compute_pipeline :: proc(
	descriptor:	Shader_Stage_Descriptor,
	group_size:	[3]int,
	location :=	#caller_location,
) -> (pipeline: Pipeline, res: Result) {

	_check_device_selected(location) or_return

	handle, metadata := _add_pipeline_metadata() or_return
	defer if res != nil do _remove_pipeline_metadata(handle)

	metadata.type = .Compute
	metadata.compute.desc = descriptor

	when TARGET_API == .Vulkan {
		vk_create_compute_pipeline(metadata, descriptor, group_size) or_return
	} else when TARGET_API == .Metal_3 {
		m3_create_compute_pipeline(metadata, descriptor, group_size) or_return
	}

	return handle, nil
}

create_render_pipeline :: proc(
	vertex_descriptor:	Shader_Stage_Descriptor,
	fragment_descriptor:	Shader_Stage_Descriptor,
	render_descriptor:	struct {},
	location :=		#caller_location,
) -> (pipeline: Pipeline, res: Result) {

	_check_device_selected(location) or_return
	
	unimplemented()
}

destroy_pipeline :: proc(pipeline: Pipeline, location := #caller_location) {
	
	_check_device_selected(location)
	
	metadata, metadata_res := _metadata_of(pipeline)
	if metadata_res != nil {
		return
	}

	when TARGET_API == .Vulkan {
		vk_destroy_pipeline(metadata)
	} else when TARGET_API == .Metal_3 {
		m3_destroy_pipeline(metadata)
	}

	_remove_pipeline_metadata(pipeline)
}

load_bytecode_of :: proc(
	shader_name: string,
	collection_path: string,
	allocator: runtime.Allocator,
) -> (bytecode: []byte, err: os.Error) {

	// bytecode_extension :: ".spv" when TARGET_API == .Vulkan else ".metallib"
	bytecode_extension: string
	if TARGET_API == .Vulkan && _settings.vk.shader_format == .Spirv {
		bytecode_extension = ".spv"
	} else {
		bytecode_extension = ".metallib"
	}

	bytecode_path := strings.concatenate({
		collection_path,
		"/",
		shader_name,
		bytecode_extension,
	}, context.temp_allocator) or_return

	bytecode = os.read_entire_file(bytecode_path, allocator) or_return

	return
}

_pipeline_metadata_of :: proc(pipeline: Pipeline) -> (^_Pipeline_Metadata, Result) {
	metadata, ok := hm.get(&_pipelines, pipeline)
	if !ok {
		return nil, .Invalid_Pipeline
	}
	
	return metadata, nil
}

_add_pipeline_metadata :: proc() -> (pipeline: Pipeline, metadata: ^_Pipeline_Metadata, res: Result) {
	pipeline = hm.add(&_pipelines, _Pipeline_Metadata {}) or_return
	metadata = hm.get(&_pipelines, pipeline)

	return
}

_remove_pipeline_metadata :: proc(pipeline: Pipeline) {
	hm.remove(&_pipelines, pipeline)
}

@(rodata)
_SIZE_OF_CONSTANT_TYPE := [Constant_Type]int {
	.U32	= 4,
	.F32	= 4,
}

