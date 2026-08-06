#+build darwin
package gfx

import NS "core:sys/darwin/Foundation"
import MTL "vendor:darwin/Metal"
import "core:log"
import "shared:darwext/dispatch"

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
	descriptor:	Shader_Stage_Descriptor,
	group_size:	[3]int,
) -> Result {

	bytecode_data := dispatch.data_create(
		raw_data(descriptor.bytecode),
		cast(uintptr)len(descriptor.bytecode),
		dispatch.get_global_queue(),
		dispatch.DATA_DESTRUCTOR_DEFAULT,
	)

	library, library_err := m3_device->newLibraryWithData(bytecode_data)
	if library_err != nil {
		log.errorf("%s - %s", library_err->localizedFailureReason()->odinString(), library_err->localizedDescription()->odinString())
		return .Invalid_Pipeline
	}

	function_name := NS.String.alloc()->initWithOdinString(descriptor.entrypoint)
	defer function_name->release()

	function: ^MTL.Function
	if descriptor.constants == nil {
		function = library->newFunctionWithName(function_name)
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
		log.errorf("%s - %s", library_err->localizedFailureReason(), library_err->localizedDescription())
			return .Invalid_Pipeline
		}
	}

	return nil
}

m3_destroy_pipeline :: proc(metadata: ^_Pipeline_Metadata) {
	switch metadata.type {
	case .Compute:
		metadata.m3.compute.pipeline->release()
		metadata.m3.compute.function->release()
		metadata.m3.compute.library->release()

	case .Render:
	}
}


// import hm "core:container/handle_map"
// import NS "core:sys/darwin/Foundation"
// import MTL "vendor:darwin/Metal"
// import "shared:darwext/dispatch"

// m3_Library_Metadata :: struct {
// 	handle:		Library,
// 	library:	^MTL.Library,
// }

// m3_Pipeline_Metadata :: struct {
// 	handle:		Pipeline,

// 	group_size: [3]int,

// 	pipeline:	union {
// 		^MTL.ComputePipelineState,
// 		^MTL.RenderPipelineState,
// 	},
// }

// m3_libraries: hm.Dynamic_Handle_Map(m3_Library_Metadata, Library)
// m3_pipelines: hm.Dynamic_Handle_Map(m3_Pipeline_Metadata, Pipeline)

// m3_create_library_from_bytes :: proc(bytes: []byte) -> (handle: Library, res: Result) {
// 	queue := dispatch.get_main_queue()
// 	defer queue->release()

// 	data := dispatch.data_create(raw_data(bytes), cast(uintptr)len(bytes), queue, dispatch.DATA_DESTRUCTOR_DEFAULT)
// 	defer data->release()

// 	library, error := m3_device->newLibraryWithData(data)
// 	if error != nil {
// 		return {}, nil
// 	}

// 	handle = hm.add(&m3_libraries, m3_Library_Metadata {
// 		library = library,
// 	}) or_return

// 	return handle, nil
// }

// m3_create_library_from_file :: proc(path: string) -> (handle: Library, res: Result) {
// 	objc_path := NS.String.alloc()->initWithOdinString(path)
// 	defer objc_path->release()

// 	url := NS.URL.alloc()->initWithString(objc_path)
// 	defer url->release()

// 	library, error := m3_device->newLibraryWithURL(url)
// 	if error != nil {
// 		return {}, nil
// 	}

// 	handle = hm.add(&m3_libraries, m3_Library_Metadata {
// 		library = library,
// 	}) or_return
	
// 	return handle, nil
// }

// m3_create_compute_pipeline :: proc(
// 	library: Library, name: string,
// 	constants: []Constant,
// 	group_size: [3]int,
// ) -> (handle: Pipeline, res: Result) {
	
// 	library_metadata, library_ok := hm.get(&m3_libraries, library)
// 	if !library_ok {
// 		return {}, .Invalid_Library
// 	}
	
// 	objc_name := NS.String.alloc()->initWithOdinString(name)
// 	defer objc_name->release()

// 	mtl_constants := m3_constants_to_mtl(constants) 
// 	defer mtl_constants->release()

// 	function, function_err := library_metadata.library->newFunctionWithConstantValues(objc_name, mtl_constants)
// 	if function_err != nil {
// 		return {}, nil
// 	}

// 	pipeline, pipeline_err := m3_device->newComputePipelineStateWithFunction(function)
// 	if pipeline_err != nil {
// 		return {}, nil
// 	}

// 	handle = hm.add(&m3_pipelines, m3_Pipeline_Metadata {
// 		pipeline	= pipeline,
// 		group_size	= group_size,
// 	})

// 	return handle, nil
// }

// m3_constants_to_mtl :: proc(constants: []Constant) -> ^MTL.FunctionConstantValues {
// 	values := MTL.FunctionConstantValues.alloc()->init()

// 	for constant in constants {
// 		values->setConstantValue(
// 			constant.value,
// 			m3_CONSTANT_TYPE_TO_MTL[constant.type],
// 			cast(NS.UInteger)constant.index,
// 		)
// 	}

// 	return values
// }

@(rodata)
m3_CONSTANT_TYPE_TO_MTL := [Constant_Type]MTL.DataType {
	.U32 = .UInt,
	.F32 = .Float,
}

