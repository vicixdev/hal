package vicixdev_gfx

import "core:strings"
import "core:bytes"
import "core:sync"
import "core:mem"
import vk "vendor:vulkan"

vk_Shader_Stage_Metadata :: struct {
	module:		vk.ShaderModule,
}

vk_Pipeline_Metadata :: struct {
	using type_metadata: struct #raw_union {
		compute:	vk_Shader_Stage_Metadata,
		render:		struct {
			vertex:		vk_Shader_Stage_Metadata,
			fragment:	vk_Shader_Stage_Metadata,
		},
	},

	pipeline:	vk.Pipeline,
}

vk_create_compute_pipeline :: proc(
	metadata:	^_Pipeline_Metadata,
	descriptor:	Shader_Stage_Descriptor,
) -> Result {

	shader_module_info := vk_shader_stage_descriptor_to_vk(descriptor)
	vk_res := vk.CreateShaderModule(vk_device, &shader_module_info, nil, &metadata.vk.compute.module)
	if vk_res == .ERROR_INITIALIZATION_FAILED || vk_res == .ERROR_INVALID_SHADER_NV {
		return .Invalid_Pipeline_Bytecode
	} else if vk_res != .SUCCESS {
		return vk_result_to_gfx(vk_res)
	}

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
			&metadata.vk.pipeline,
		)) or_return
	}
	
	return nil
}

vk_create_render_pipeline :: proc(
	metadata: ^_Pipeline_Metadata,
	descriptor: Render_Pipeline_Descriptor,
	blend_metadata: ^_Blend_State_Metadata,
) -> Result {
	vertex_module_info := vk_shader_stage_descriptor_to_vk(descriptor.vertex_stage)
	vertex_module_res := vk.CreateShaderModule(vk_device, &vertex_module_info, nil, &metadata.vk.render.vertex.module)
	if vertex_module_res == .ERROR_INITIALIZATION_FAILED || vertex_module_res == .ERROR_INVALID_SHADER_NV {
		return .Invalid_Pipeline_Bytecode
	} else if vertex_module_res != .SUCCESS {
		return vk_result_to_gfx(vertex_module_res)
	}

	vertex_specialization: vk.SpecializationInfo
	if descriptor.vertex_stage.constants != nil {
		vk_constants_to_specialization_info(descriptor.vertex_stage)
	}

	fragment_module_info := vk_shader_stage_descriptor_to_vk(descriptor.fragment_stage)
	fragment_module_res := vk.CreateShaderModule(vk_device, &fragment_module_info, nil, &metadata.vk.render.fragment.module)
	if fragment_module_res == .ERROR_INITIALIZATION_FAILED || fragment_module_res == .ERROR_INVALID_SHADER_NV {
		return .Invalid_Pipeline_Bytecode
	} else if fragment_module_res != .SUCCESS {
		return vk_result_to_gfx(fragment_module_res)
	}

	fragment_specialization: vk.SpecializationInfo
	if descriptor.fragment_stage.constants != nil {
		vk_constants_to_specialization_info(descriptor.fragment_stage)
	}

	pipeline_info := vk_make_render_pipeline_desc(
		metadata.vk.render.vertex.module,
		metadata.vk.render.fragment.module,
		descriptor,
		blend_metadata,
		&vertex_specialization,
		&fragment_specialization,
	)

	if sync.mutex_guard(&vk_pipeline_cache_mutex) {
		vk_call(vk.CreateGraphicsPipelines(
			vk_device,
			vk_pipeline_cache,
			1,
			&pipeline_info,
			nil,
			&metadata.vk.pipeline,
		)) or_return
	}

	return {}
}

vk_destroy_pipeline :: proc(metadata: ^_Pipeline_Metadata) {
	switch metadata.type {
	case .Compute:
		vk.DestroyShaderModule(vk_device, metadata.vk.compute.module, nil)
		vk.DestroyPipeline(vk_device, metadata.vk.pipeline, nil)

	case .Render:
		vk.DestroyShaderModule(vk_device, metadata.vk.render.vertex.module, nil)
		vk.DestroyShaderModule(vk_device, metadata.vk.render.fragment.module, nil)
		vk.DestroyPipeline(vk_device, metadata.vk.pipeline, nil)
	}
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
		}, _temp_allocator)

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
		sType			= .PIPELINE_SHADER_STAGE_CREATE_INFO,
		stage			= { .COMPUTE },
		module			= module,
		pName			= strings.clone_to_cstring(descriptor.entrypoint, _temp_allocator),
		pSpecializationInfo	= specialization,
	}

	return
}


vk_make_render_pipeline_desc :: proc(
	vertex_module:			vk.ShaderModule,
	fragment_module:		vk.ShaderModule,
	descriptor:			Render_Pipeline_Descriptor,
	blend_metadata:			^_Blend_State_Metadata,
	vertex_specialization:		^vk.SpecializationInfo,
	fragment_specialization:	^vk.SpecializationInfo,
) -> (info: vk.GraphicsPipelineCreateInfo) {
	
	stages := make([]vk.PipelineShaderStageCreateInfo, 2, _temp_allocator)
	stages[0] = vk.PipelineShaderStageCreateInfo {
		sType			= .PIPELINE_SHADER_STAGE_CREATE_INFO,
		stage			= { .VERTEX },
		module			= vertex_module,
		pName			= strings.clone_to_cstring(descriptor.vertex_stage.entrypoint, _temp_allocator),
		pSpecializationInfo	= vertex_specialization,
	}
	stages[1] = vk.PipelineShaderStageCreateInfo {
		sType			= .PIPELINE_SHADER_STAGE_CREATE_INFO,
		stage			= { .FRAGMENT },
		module			= fragment_module,
		pName			= strings.clone_to_cstring(descriptor.fragment_stage.entrypoint, _temp_allocator),
		pSpecializationInfo	= fragment_specialization,
	}

	vertex_input_state := new(vk.PipelineVertexInputStateCreateInfo, _temp_allocator)
	vertex_input_state^ = {
		sType	= .PIPELINE_VERTEX_INPUT_STATE_CREATE_INFO,
	}

	input_assembly_state := new(vk.PipelineInputAssemblyStateCreateInfo, _temp_allocator)
	input_assembly_state^ = {
		sType		= .PIPELINE_INPUT_ASSEMBLY_STATE_CREATE_INFO,
		topology	= vk_TOPOLOGY_TO_VK[descriptor.topology],
	}

	viewport_state := new(vk.PipelineViewportStateCreateInfo, _temp_allocator)
	viewport_state^ = {
		sType		= .PIPELINE_VIEWPORT_STATE_CREATE_INFO,
		viewportCount	= 1,
		scissorCount	= 1,
	}

	rasterization_state := new(vk.PipelineRasterizationStateCreateInfo, _temp_allocator)
	rasterization_state^ = {
		sType			= .PIPELINE_RASTERIZATION_STATE_CREATE_INFO,
		polygonMode		= .FILL,
		cullMode		= vk_CULL_MODE_TO_VK[descriptor.cull],
		frontFace		= .CLOCKWISE,
		lineWidth		= 1.0,
	}

	color_blend_states := make(
		[]vk.PipelineColorBlendAttachmentState,
		len(descriptor.color_formats),
		_temp_allocator,
	)
	for format, i in descriptor.color_formats {
		color_blend_state: vk.PipelineColorBlendAttachmentState

		if blend_metadata != nil {
			color_blend_state.blendEnable = true
			color_blend_state.colorBlendOp		= vk_BLEND_OP_TO_VK[blend_metadata.color_op]
			color_blend_state.srcColorBlendFactor	= vk_BLEND_FACTOR_TO_VK[blend_metadata.source_color_factor]
			color_blend_state.dstColorBlendFactor	= vk_BLEND_FACTOR_TO_VK[blend_metadata.destination_color_factor]
			color_blend_state.alphaBlendOp		= vk_BLEND_OP_TO_VK[blend_metadata.alpha_op]
			color_blend_state.srcAlphaBlendFactor	= vk_BLEND_FACTOR_TO_VK[blend_metadata.source_alpha_factor]
			color_blend_state.dstAlphaBlendFactor	= vk_BLEND_FACTOR_TO_VK[blend_metadata.destination_alpha_factor]
		}
		color_blend_state.colorWriteMask = vk_PIXEL_FORMAT_TO_VK_COLOR_COMPONENTS[format]

		color_blend_states[i] = color_blend_state
	}
	color_blend_state := new(vk.PipelineColorBlendStateCreateInfo, _temp_allocator)
	color_blend_state^ = {
		sType			= .PIPELINE_COLOR_BLEND_STATE_CREATE_INFO,
		attachmentCount		= cast(u32)len(color_blend_states),
		pAttachments		= raw_data(color_blend_states),
	}

	multisample_state := new(vk.PipelineMultisampleStateCreateInfo, _temp_allocator)
	multisample_state^ = {
		sType			= .PIPELINE_MULTISAMPLE_STATE_CREATE_INFO,
		rasterizationSamples	= vk_SAMPLE_COUNT_TO_VK[descriptor.sample_count],
		alphaToCoverageEnable	= cast(b32)descriptor.alpha_to_coverage,
	}

	color_attachment_formats := make([]vk.Format, len(descriptor.color_formats), _temp_allocator)
	for format, i in descriptor.color_formats {
		color_attachment_formats[i] = vk_PIXEL_FORMAT_TO_VK[format]
	}
	render_info := new(vk.PipelineRenderingCreateInfo, _temp_allocator)
	render_info^ = {
		sType			= .PIPELINE_RENDERING_CREATE_INFO,
		colorAttachmentCount	= cast(u32)len(color_attachment_formats),
		pColorAttachmentFormats	= raw_data(color_attachment_formats),
		depthAttachmentFormat	= vk_PIXEL_FORMAT_TO_VK[descriptor.depth_format],
		stencilAttachmentFormat	= vk_PIXEL_FORMAT_TO_VK[descriptor.stencil_format],
	}

	depth_stencil_state := new(vk.PipelineDepthStencilStateCreateInfo, _temp_allocator)
	depth_stencil_state^ = {
		sType	= .PIPELINE_DEPTH_STENCIL_STATE_CREATE_INFO,
		depthTestEnable		= false,
		stencilTestEnable	= false,
	}

	@(static)
	dynamic_states := []vk.DynamicState {
		.VIEWPORT,
		.SCISSOR,
		.BLEND_CONSTANTS,
		.DEPTH_BOUNDS,
		.DEPTH_TEST_ENABLE,
		.DEPTH_WRITE_ENABLE,
		.DEPTH_BIAS,
		.DEPTH_BIAS_ENABLE,
		.DEPTH_COMPARE_OP,
		.STENCIL_COMPARE_MASK,
		.STENCIL_WRITE_MASK,
		.STENCIL_REFERENCE,
		.STENCIL_TEST_ENABLE,
		.STENCIL_OP,
	}
	dynamic_state := new(vk.PipelineDynamicStateCreateInfo, _temp_allocator)
	dynamic_state^ = {
		sType			= .PIPELINE_DYNAMIC_STATE_CREATE_INFO,
		dynamicStateCount	= cast(u32)len(dynamic_states),
		pDynamicStates		= raw_data(dynamic_states),
	}

	info.sType			= .GRAPHICS_PIPELINE_CREATE_INFO
	info.pNext			= render_info
	info.stageCount			= cast(u32)len(stages)
	info.pStages			= raw_data(stages)
	info.pVertexInputState		= vertex_input_state
	info.pViewportState		= viewport_state
	info.pInputAssemblyState	= input_assembly_state
	info.pRasterizationState	= rasterization_state
	info.pMultisampleState		= multisample_state
	info.pColorBlendState		= color_blend_state
	info.pDepthStencilState		= depth_stencil_state
	info.pDynamicState		= dynamic_state
	info.layout			= vk_render_pipeline_layout

	return
}

vk_constants_to_specialization_info :: proc(
	descriptor:	Shader_Stage_Descriptor,
) -> (info: vk.SpecializationInfo) {

	required_space_for_constants := 0
	for constant in descriptor.constants {
		required_space_for_constants += _SIZE_OF_CONSTANT_TYPE[constant.type]
	}

	constants_buffer: bytes.Buffer
	bytes.buffer_init_allocator(&constants_buffer, 0, required_space_for_constants, _temp_allocator)
	for constant in descriptor.constants {
		bytes.buffer_write_ptr(&constants_buffer, constant.value, _SIZE_OF_CONSTANT_TYPE[constant.type])
	}

	entries := make([]vk.SpecializationMapEntry, len(descriptor.constants), _temp_allocator)
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

@(rodata)
vk_TOPOLOGY_TO_VK := [Topology]vk.PrimitiveTopology {
	.Triangle_List	= .TRIANGLE_LIST,
	.Triangle_Strip	= .TRIANGLE_STRIP,
}

@(rodata)
vk_CULL_MODE_TO_VK := [Cull_Mode]vk.CullModeFlags {
	.None			= {},
	.Clockwise		= { .FRONT },
	.Counter_Clockwise	= { .BACK },
}

@(rodata)
vk_PIXEL_FORMAT_TO_VK_COLOR_COMPONENTS := [Pixel_Format]vk.ColorComponentFlags {
	.None			= {},
	.R8_Unorm		= { .R, },
	.RG8_Unorm		= { .R, .G },
	.RGBA8_Unorm		= { .R, .G, .B, .A },
	.RGBA8_Srgb		= { .R, .G, .B, .A },
	.BGRA8_Unorm		= { .R, .G, .B, .A },
	.BGRA8_Srgb		= { .R, .G, .B, .A },
	.R16_Float		= { .R },
	.RG16_Float		= { .R, .G },
	.RGBA16_Float		= { .R, .G, .B, .A },
	.RGBA16_Unorm		= { .R, .G, .B, .A },
	.R16_Unorm		= { .R },
	.RG16_Unorm		= { .R, .G },
	.R32_Float		= { .R },
	.RG32_Float		= { .R, .G },
	.RGBA32_Float		= { .R, .G, .B, .A },
	.RG11B10_Float		= { .R, .G, .B },
	.RGB10_A2_Unorm		= { .R, .G, .B, .A },
	.RGB10_A2_Uint		= { .R, .G, .B, .A },
	.D32_Float		= {},
	.D24_Unorm_S8_Uint	= {},
	.D32_Float_S8_Uint	= {},
	.D16_Unorm		= {},
}

