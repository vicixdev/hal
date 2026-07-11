#+build darwin
package gfx

import hm "core:container/handle_map"
import NS "core:sys/darwin/Foundation"
import MTL "vendor:darwin/Metal"
import "shared:darwext/dispatch"

_Library_Metadata :: struct {
	handle:		Library,
	library:	^MTL.Library,
}

_Pipeline_Metadata :: struct {
	handle:		Pipeline,

	group_size: [3]int,

	pipeline:	union {
		^MTL.ComputePipelineState,
		^MTL.RenderPipelineState,
	},
}

_libraries: hm.Dynamic_Handle_Map(_Library_Metadata, Library)
_pipelines: hm.Dynamic_Handle_Map(_Pipeline_Metadata, Pipeline)

_create_library_from_bytes :: proc(bytes: []byte) -> (handle: Library, res: Result) {
	queue := dispatch.get_main_queue()
	defer queue->release()

	data := dispatch.data_create(raw_data(bytes), cast(uintptr)len(bytes), queue, dispatch.DATA_DESTRUCTOR_DEFAULT)
	defer data->release()

	library, error := _device->newLibraryWithData(data)
	if error != nil {
		return {}, nil
	}

	handle = hm.add(&_libraries, _Library_Metadata {
		library = library,
	}) or_return

	return handle, nil
}

_create_library_from_file :: proc(path: string) -> (handle: Library, res: Result) {
	objc_path := NS.String.alloc()->initWithOdinString(path)
	defer objc_path->release()

	url := NS.URL.alloc()->initWithString(objc_path)
	defer url->release()

	library, error := _device->newLibraryWithURL(url)
	if error != nil {
		return {}, nil
	}

	handle = hm.add(&_libraries, _Library_Metadata {
		library = library,
	}) or_return
	
	return handle, nil
}

_create_compute_pipeline :: proc(
	library: Library, name: string,
	constants: []Constant,
	group_size: [3]int,
) -> (handle: Pipeline, res: Result) {
	
	library_metadata, library_ok := hm.get(&_libraries, library)
	if !library_ok {
		return {}, .Invalid_Library
	}
	
	objc_name := NS.String.alloc()->initWithOdinString(name)
	defer objc_name->release()

	mtl_constants := _constants_to_mtl(constants) 
	defer mtl_constants->release()

	function, function_err := library_metadata.library->newFunctionWithConstantValues(objc_name, mtl_constants)
	if function_err != nil {
		return {}, nil
	}

	pipeline, pipeline_err := _device->newComputePipelineStateWithFunction(function)
	if pipeline_err != nil {
		return {}, nil
	}

	handle = hm.add(&_pipelines, _Pipeline_Metadata {
		pipeline	= pipeline,
		group_size	= group_size,
	})

	return handle, nil
}

_constants_to_mtl :: proc(constants: []Constant) -> ^MTL.FunctionConstantValues {
	values := MTL.FunctionConstantValues.alloc()->init()

	for constant in constants {
		values->setConstantValue(
			constant.value,
			_CONSTANT_TYPE_TO_MTL[constant.type],
			cast(NS.UInteger)constant.index,
		)
	}

	return values
}

@(rodata)
_CONSTANT_TYPE_TO_MTL := [Constant_Type]MTL.DataType {
	.U32 = .UInt,
	.F32 = .Float,
}

