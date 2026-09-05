package vicixdev_gfx

import "base:runtime"
import "core:os"
import "core:sync"
import "core:slice"
import "core:strings"
import hm "core:container/handle_map"

Pipeline :: distinct Handle

Topology :: enum {
	Triangle_List,
	Triangle_Strip,
}

Cull_Mode :: enum {
	None,
	Clockwise,
	Counter_Clockwise,
}

Constant_Type :: enum {
	U32,
	F32,
	// TODO: Add constant types
}

Constant :: struct {
	index:	int,
	// TODO: Switch to any
	value:	rawptr,
	type:	Constant_Type,
}

Shader_Stage_Descriptor :: struct {
	bytecode:	[]byte,
	entrypoint:	string,
	constants:	[]Constant,
}

Compute_Pipeline_Descriptor :: struct {
	using stage:	Shader_Stage_Descriptor,

	group_size:	[3]int,
}

Render_Pipeline_Descriptor :: struct {
	vertex_stage:		Shader_Stage_Descriptor,
	fragment_stage:		Shader_Stage_Descriptor,

	topology:		Topology,
	cull:			Cull_Mode,
	alpha_to_coverage:	bool,
	// supports_dual_blending:	bool,
	sample_count:		int,
	color_formats:		[]Pixel_Format,
	depth_format:		Pixel_Format,
	stencil_format:		Pixel_Format,

	blend_state:		Maybe(Blend_State),
}

_Pipeline_Type :: enum {
	Compute,
	Render,
}

_Pipeline_Metadata :: struct {
	handle:	Pipeline,
	type:	_Pipeline_Type,

	using type_metadata: struct #raw_union {
		compute:	Compute_Pipeline_Descriptor,
		render:		Render_Pipeline_Descriptor,
	},

	using platform: struct #raw_union {
		vk:	vk_Pipeline_Metadata,
		m3:	m3_Pipeline_Metadata,
	},
}

_pipelines:		hm.Dynamic_Handle_Map(_Pipeline_Metadata, Pipeline)
_pipelines_mutex:	sync.RW_Mutex

create_compute_pipeline :: proc(
	descriptor:	Compute_Pipeline_Descriptor,
	location :=	#caller_location,
) -> (pipeline: Pipeline, res: Result) {

	_check_device_selected(location) or_return

	handle, metadata := _add_pipeline_metadata() or_return
	defer if res != nil do _remove_pipeline_metadata(handle)

	metadata.type = .Compute
	metadata.compute = descriptor

	when TARGET_API == .Vulkan {
		res = vk_create_compute_pipeline(metadata, descriptor)
	} else when TARGET_API == .Metal_3 {
		res = m3_create_compute_pipeline(metadata, descriptor)
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
	descriptor:	Render_Pipeline_Descriptor,
	location :=	#caller_location,
) -> (pipeline: Pipeline, res: Result) {

	blend_metadata: ^_Blend_State_Metadata
	if blend_state, has_blend_state := descriptor.blend_state.?; has_blend_state {
		blend_res: Result
		blend_metadata, blend_res = _metadata_of(blend_state)
		_check_blend_state_handle(blend_res, blend_state, location) or_return
	}

	handle, metadata := _add_pipeline_metadata() or_return
	defer if res != nil do _remove_pipeline_metadata(handle)

	metadata.type = .Render
	metadata.render = descriptor
	metadata.render.color_formats = slice.clone(descriptor.color_formats, _generic_allocator)

	when TARGET_API == .Vulkan {
		res = vk_create_render_pipeline(metadata, descriptor, blend_metadata)
	} else when TARGET_API == .Metal_3 {
		res = m3_create_render_pipeline(metadata, descriptor, blend_metadata)
	}

	_check_specific_result(
		res,
		.Invalid_Pipeline_Bytecode,
		.Error,
		"Invalid Pipeline Bytecode",
		"Could not create the render pipeline because its bytecode (vertex at 0x%x, %d bytes, `%s` " +
		"entrypoint - fragment at 0x%x, %d bytes, `%s` entrypoint) is malformed.",
		raw_data(descriptor.vertex_stage.bytecode),
		len(descriptor.vertex_stage.bytecode),
		descriptor.vertex_stage.entrypoint,
		raw_data(descriptor.fragment_stage.bytecode),
		len(descriptor.fragment_stage.bytecode),
		descriptor.fragment_stage.entrypoint,
	) or_return
	_check_specific_result(
		res,
		.Invalid_Pipeline_Constants,
		.Error,
		"Invalid Pipeline Constants",
		"Could not create the render pipeline (vertex at 0x%x, %d bytes, `%s` entrypoint - fragment at 0x%x, " +
		"%d bytes, `%s` entrypoint) because its constants are not valid for the specified bytecode.",
		raw_data(descriptor.vertex_stage.bytecode),
		len(descriptor.vertex_stage.bytecode),
		descriptor.vertex_stage.entrypoint,
		raw_data(descriptor.fragment_stage.bytecode),
		len(descriptor.fragment_stage.bytecode),
		descriptor.fragment_stage.entrypoint,
	) or_return
	_check_generic_backend_error(res, location) or_return

	return handle, nil
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

	if metadata.type == .Render {
		delete(metadata.render.color_formats, _generic_allocator)
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
	sync.shared_guard(&_pipelines_mutex)

	metadata, ok := hm.get(&_pipelines, pipeline)
	if !ok {
		return nil, .Invalid_Pipeline
	}
	
	return metadata, nil
}

_add_pipeline_metadata :: proc() -> (pipeline: Pipeline, metadata: ^_Pipeline_Metadata, res: Result) {
	sync.guard(&_pipelines_mutex)

	pipeline = hm.add(&_pipelines, _Pipeline_Metadata {}) or_return
	metadata = hm.get(&_pipelines, pipeline)

	return
}

_remove_pipeline_metadata :: proc(pipeline: Pipeline) {
	sync.guard(&_pipelines_mutex)

	hm.remove(&_pipelines, pipeline)
}

@(rodata)
_SIZE_OF_CONSTANT_TYPE := [Constant_Type]int {
	.U32	= 4,
	.F32	= 4,
}

