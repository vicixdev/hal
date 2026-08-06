package gfx

import "core:strings"
import "core:bytes"
import "core:sync"
import "core:mem"
import vk "vendor:vulkan"

vk_Shader_Stage_Metadata :: struct {
	module:		vk.ShaderModule,
	pipeline:	vk.Pipeline,
}

vk_Pipeline_Metadata :: struct {
	using type_metadata: struct #raw_union {
		compute:	vk_Shader_Stage_Metadata,
		render:		struct {
			vertex:		vk_Shader_Stage_Metadata,
			fragment:	vk_Shader_Stage_Metadata,
		},
	},
}

vk_create_compute_pipeline :: proc(
	metadata:	^_Pipeline_Metadata,
	descriptor:	Shader_Stage_Descriptor,
	group_size:	[3]int,
) -> Result {

	shader_module_info := vk_shader_stage_descriptor_to_vk(descriptor)
	vk_call(vk.CreateShaderModule(vk_device, &shader_module_info, nil, &metadata.vk.compute.module))

	pipeline_info: vk.ComputePipelineCreateInfo
	if descriptor.constants != nil {
		specialization_info := vk_constants_to_specialization_info(descriptor)
		pipeline_info = vk_make_compute_pipeline_desc(
			metadata.vk.compute.module,
			descriptor,
			&specialization_info,
		)
	} else {
		pipeline_info = vk_make_compute_pipeline_desc(
			metadata.vk.compute.module,
			descriptor,
			nil,
		)
	}

	if sync.mutex_guard(&vk_pipeline_cache_mutex) {
		vk_call(vk.CreateComputePipelines(
			vk_device,
			vk_pipeline_cache,
			1,
			&pipeline_info,
			nil,
			&metadata.vk.compute.pipeline,
		))
	}
	
	return nil
}

vk_destroy_pipeline :: proc(metadata: ^_Pipeline_Metadata) {
	switch metadata.type {
	case .Compute:
		vk.DestroyShaderModule(vk_device, metadata.vk.compute.module, nil)
		vk.DestroyPipeline(vk_device, metadata.vk.compute.pipeline, nil)

	case .Render:
	}
}

vk_create_render_pipeline :: proc() -> (handle: Pipeline) {
	return
}

vk_shader_stage_descriptor_to_vk :: proc(descriptor: Shader_Stage_Descriptor) -> (info: vk.ShaderModuleCreateInfo) {
	kMVKMagicNumberMSLCompiledCode: u32 : 0x19981215

	info.sType	= .SHADER_MODULE_CREATE_INFO

	if _settings.vk.shader_format == .Spirv {
		info.codeSize	= len(descriptor.bytecode)
		info.pCode	= cast([^]u32)raw_data(descriptor.bytecode)
	} else {
		code := bytes.concatenate({
			mem.any_to_bytes(kMVKMagicNumberMSLCompiledCode),
			descriptor.bytecode,
		}, context.temp_allocator)

		info.codeSize	= len(code)
		info.pCode	= cast([^]u32)raw_data(code)
	}

	return
}

vk_make_compute_pipeline_desc :: proc(
	module:		vk.ShaderModule,
	descriptor:	Shader_Stage_Descriptor,
	specialization:	^vk.SpecializationInfo,
) -> (info: vk.ComputePipelineCreateInfo){

	info.sType	= .COMPUTE_PIPELINE_CREATE_INFO

	info.layout	= vk_compute_pipeline_layout
	info.stage	= {
		stage			= { .COMPUTE },
		module			= module,
		pName			= strings.clone_to_cstring(descriptor.entrypoint, context.temp_allocator),
		pSpecializationInfo	= specialization,
	}

	return
}

vk_constants_to_specialization_info :: proc(
	descriptor:	Shader_Stage_Descriptor,
	allocator :=	context.temp_allocator,
) -> (info: vk.SpecializationInfo) {

	required_space_for_constants := 0
	for constant in descriptor.constants {
		required_space_for_constants += _SIZE_OF_CONSTANT_TYPE[constant.type]
	}

	constants_buffer: bytes.Buffer
	bytes.buffer_init_allocator(&constants_buffer, 0, required_space_for_constants, allocator)
	for constant in descriptor.constants {
		bytes.buffer_write_ptr(&constants_buffer, constant.value, _SIZE_OF_CONSTANT_TYPE[constant.type])
	}

	entries := make([]vk.SpecializationMapEntry, len(descriptor.constants), allocator)
	offset := 0
	for &entry, i in entries {
		size := _SIZE_OF_CONSTANT_TYPE[descriptor.constants[i].type]

		entry.constantID	= cast(u32)descriptor.constants[i].index
		entry.offset		= cast(u32)offset
		entry.size		= size

		offset += size
	}

	info.dataSize		= required_space_for_constants
	info.pData		= raw_data(constants_buffer.buf[:])
	info.mapEntryCount	= cast(u32)len(entries)
	info.pMapEntries	= raw_data(entries)
	
	return
}

