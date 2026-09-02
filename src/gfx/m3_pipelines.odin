#+build darwin
package vicixdev_gfx

import NS "core:sys/darwin/Foundation"
import MTL "vendor:darwin/Metal"
import "darwext/dispatch"

m3_Pipeline_Stage_Metadata :: struct {
	library:	^MTL.Library,
	function:	^MTL.Function,
}

m3_Pipeline_Metadata :: struct {
	using type_metadata: struct #raw_union {
		compute:	struct {
			using stage:	m3_Pipeline_Stage_Metadata,
			pipeline:	^MTL.ComputePipelineState,
		},
		render:		struct {
			vertex:		m3_Pipeline_Stage_Metadata,
			fragment:	m3_Pipeline_Stage_Metadata,
			pipeline:	^MTL.RenderPipelineState,
		},
	},
}

m3_create_compute_pipeline :: proc(
	metadata:	^_Pipeline_Metadata,
	descriptor:	Compute_Pipeline_Descriptor,
) -> Result {
	NS.scoped_autoreleasepool()

	library, function := m3_compile_pipeline_stage(descriptor.stage) or_return

	pipeline, pipeline_err := m3_device->newComputePipelineStateWithFunction(function)
	if pipeline_err != nil {
		_log_generic_message(
			.Error,
			"Shader compilation error",
			"Could not create a compute pipeline from function `%s`: %s -- %s",
			descriptor.entrypoint,
			pipeline_err->localizedFailureReason()->odinString(),
			pipeline_err->localizedDescription()->odinString(),
		)
		pipeline_err->release()
		return .Generic_Backend_Error,
	}

	metadata.m3.compute.library = library
	metadata.m3.compute.function = function
	metadata.m3.compute.pipeline = pipeline

	return nil
}

m3_create_render_pipeline :: proc(
	metadata: ^_Pipeline_Metadata,
	descriptor: Render_Pipeline_Descriptor,
	blend_metadata: ^_Blend_State_Metadata,
) -> Result {
	NS.scoped_autoreleasepool()

	vertex_library, vertex_function := m3_compile_pipeline_stage(descriptor.vertex_stage) or_return
	fragment_library, fragment_function := m3_compile_pipeline_stage(descriptor.fragment_stage) or_return

	pipeline_descriptor := m3_render_pipeline_descriptor_to_mtl(
		descriptor,
		blend_metadata,
		vertex_function,
		fragment_function,
	)

	pipeline, pipeline_err := m3_device->newRenderPipelineStateWithDescriptor(pipeline_descriptor)
	if pipeline_err != nil {
		_log_generic_message(
			.Error,
			"Shader compilation error",
			"Could not create a render pipeline from functions `%s` and `%s`: %s -- %s",
			descriptor.vertex_stage.entrypoint,
			descriptor.fragment_stage.entrypoint,
			pipeline_err->localizedFailureReason()->odinString(),
			pipeline_err->localizedDescription()->odinString(),
		)
		pipeline_err->release()
		return .Generic_Backend_Error,
	}
	
	metadata.m3.render.fragment.library = fragment_library
	metadata.m3.render.fragment.function = fragment_function
	metadata.m3.render.vertex.library = vertex_library
	metadata.m3.render.vertex.function = vertex_function
	metadata.m3.render.pipeline = pipeline

	return nil
}

m3_destroy_pipeline :: proc(metadata: ^_Pipeline_Metadata) {
	NS.scoped_autoreleasepool()

	switch metadata.type {
	case .Compute:
		metadata.m3.compute.pipeline->release()
		metadata.m3.compute.function->release()
		metadata.m3.compute.library->release()

	case .Render:
		metadata.m3.render.pipeline->release()
		metadata.m3.render.vertex.function->release()
		metadata.m3.render.vertex.library->release()
		metadata.m3.render.fragment.function->release()
		metadata.m3.render.fragment.library->release()
	}
}

m3_render_pipeline_descriptor_to_mtl :: proc(
	descriptor:		Render_Pipeline_Descriptor,
	blend_metadata:		^_Blend_State_Metadata,
	vertex_function:	^MTL.Function,
	fragment_function:	^MTL.Function,
) -> (mtl: ^MTL.RenderPipelineDescriptor) {
	
	mtl = MTL.RenderPipelineDescriptor.alloc()->init()
	mtl->autorelease()

	mtl->setVertexFunction(vertex_function)
	mtl->setFragmentFunction(fragment_function)

	mtl->setInputPrimitiveTopology(.Triangle)
	mtl->setAlphaToCoverageEnabled(descriptor.alpha_to_coverage)
	mtl->setSampleCount(cast(NS.UInteger)descriptor.sample_count)
	
	for color_format, i in descriptor.color_formats {
		if color_format == .None {
			continue
		}

		color_attachment := MTL.RenderPipelineColorAttachmentDescriptor.alloc()->init()
		defer color_attachment->release()

		color_attachment->setPixelFormat(m3_PIXEL_FORMAT_TO_MTL[color_format])

		mtl->colorAttachments()->setObject(color_attachment, cast(NS.UInteger)i)

		if blend_metadata != nil {
			color_attachment->setBlendingEnabled(true)
			color_attachment->setRgbBlendOperation(m3_BLEND_OPERATION_TO_MTL[blend_metadata.color_op])
			color_attachment->setSourceRGBBlendFactor(
				m3_BLEND_FACTOR_TO_MTL[blend_metadata.source_color_factor])
			color_attachment->setDestinationRGBBlendFactor(
				m3_BLEND_FACTOR_TO_MTL[blend_metadata.destination_color_factor])
			color_attachment->setAlphaBlendOperation(m3_BLEND_OPERATION_TO_MTL[blend_metadata.alpha_op])
			color_attachment->setSourceAlphaBlendFactor(
				m3_BLEND_FACTOR_TO_MTL[blend_metadata.source_alpha_factor])
			color_attachment->setDestinationAlphaBlendFactor(
				m3_BLEND_FACTOR_TO_MTL[blend_metadata.destination_alpha_factor])
		}
	}

	if descriptor.depth_format != .None {
		mtl->setDepthAttachmentPixelFormat(m3_PIXEL_FORMAT_TO_MTL[descriptor.depth_format])
	}

	if descriptor.stencil_format != .None {
		mtl->setStencilAttachmentPixelFormat(m3_PIXEL_FORMAT_TO_MTL[descriptor.stencil_format])
	}


	return
}

m3_compile_pipeline_stage :: proc(
	descriptor: Shader_Stage_Descriptor,
) -> (^MTL.Library, ^MTL.Function, Result) {
	
	bytecode_data := dispatch.data_create(
		raw_data(descriptor.bytecode),
		cast(uintptr)len(descriptor.bytecode),
		dispatch.get_global_queue(),
		dispatch.DATA_DESTRUCTOR_DEFAULT,
	)
	defer bytecode_data->release()

	library, library_err := m3_device->newLibraryWithData(bytecode_data)
	if library_err != nil {
		_log_generic_message(
			.Error,
			"Shader compilation error",
			"The metal library could not compile: %s -- %s",
			library_err->localizedFailureReason()->odinString(),
			library_err->localizedDescription()->odinString(),
		)
		return nil, nil, .Invalid_Pipeline_Bytecode
	}

	function_name := NS.String.alloc()->initWithOdinString(descriptor.entrypoint)
	defer function_name->release()

	function: ^MTL.Function
	if descriptor.constants == nil {
		function = library->newFunctionWithName(function_name)
		if function == nil {
			_log_generic_message(
				.Error,
				"Shader compilation error",
				"The metal function `%v` could not compile.",
				descriptor.entrypoint,
			)
			return nil, nil, .Invalid_Pipeline_Bytecode
		}
	} else {
		constants := MTL.FunctionConstantValues.alloc()->init()
		defer constants->release()

		for constant in descriptor.constants {
			constants->setConstantValue(
				constant.value,
				m3_CONSTANT_TYPE_TO_MTL[constant.type],
				cast(NS.UInteger)constant.index,
			)
		}

		function_err: ^NS.Error
		function, function_err = library->newFunctionWithConstantValues(function_name, constants)
		if function_err != nil {
			_log_generic_message(
				.Error,
				"Shader compilation error",
				"The metal function `%s` could not be specialized: %s -- %s",
				descriptor.entrypoint,
				function_err->localizedFailureReason()->odinString(),
				function_err->localizedDescription()->odinString(),
			)
			return nil, nil, .Invalid_Pipeline_Constants
		}
	}

	return library, function, nil
}

@(rodata)
m3_CONSTANT_TYPE_TO_MTL := [Constant_Type]MTL.DataType {
	.U32 = .UInt,
	.F32 = .Float,
}

@(rodata)
m3_TOPOLOGY_TO_MTL := [Topology]MTL.PrimitiveType {
	.Triangle_List	= .Triangle,
	.Triangle_Strip	= .TriangleStrip,
}

