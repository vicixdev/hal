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
	index:	int,
	value:	rawptr,
	type:	Constant_Type,
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
		res = vk_create_compute_pipeline(metadata, descriptor, group_size)
	} else when TARGET_API == .Metal_3 {
		res = m3_create_compute_pipeline(metadata, descriptor, group_size)
	}

	_check_specific_result(
		res,
		.Invalid_Pipeline_Bytecode,
		.Error,
		"Invalid Pipeline Bytecode",
		"Could not create the compute pipeline because its bytecode (at 0x%x, %d bytes, `%s` entrypoint) is " +
		"malformed.",
		raw_data(descriptor.bytecode),
		len(descriptor.bytecode),
		descriptor.entrypoint,
	) or_return
	_check_specific_result(
		res,
		.Invalid_Pipeline_Constants,
		.Error,
		"Invalid Pipeline Constants",
		"Could not create the compute pipeline (bytecode at 0x%x - %d bytes, `%s` entrypoint) because its " +
		"constants are not valid for the specified bytecode.",
		raw_data(descriptor.bytecode),
		len(descriptor.bytecode),
		descriptor.entrypoint,
	) or_return
	_check_generic_backend_error(res, location) or_return

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
	_check_pipeline_handle(metadata_res, pipeline, location)
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
	}, _temp_allocator) or_return

	bytecode = os.read_entire_file(bytecode_path, allocator) or_return

	return
}

_check_pipeline_handle :: proc(result: Result, pipeline: Pipeline, location: runtime.Source_Code_Location) -> Result {
	_check_result(
		result,
		.Warning,
		"Invalid resource handle",
		"Invalid pipeline handle (%v).",
		pipeline,
		location=location,
	) or_return
	return nil
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

