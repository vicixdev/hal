package vicixdev_gfx

/*
Copyright (c) 2026 Vicix (https://github.com/vicixdev)

This Source Code Form is subject to the terms of the Mozilla Public
License, v. 2.0. If a copy of the MPL was not distributed with this
file, You can obtain one at https://mozilla.org/MPL/2.0/.
*/

import "core:log"
import "core:sync"
import "core:mem"
import NS "core:sys/darwin/Foundation"
import MTL "vendor:darwin/Metal"

/*
Dispatch ICPs do not need to support counts greater than 1, thus their structure is simpler than the draw specific ones.

Indirect encoding consists in the following steps:
	- Scratch-allocate one MTL.DispatchThreadgroupsIndirectArguments location from the `buffer.arguments` array at
		encode time.
	- Dispatch one compute thread translating the arguments in the gfx format into the corresponding metal ones.
Note that since the count is known at encode time (it is always 1), the ring allocation logic can run from the cpu side.

Indirect dispatch consists in a `ComputeCommandEncoder->dispatchThreadgroupsWithIndirectBuffer` call, pointing to the
previously allocated metal arguments.
*/
_m3_ICP_Dispatch_Metadata :: struct {
	/*
	Gpu buffer of
		struct {
			arguments:	[pool.call_count]MTL.DispatchThreadgroupsIndirectArguments,
		}
	*/
	buffer:	^MTL.Buffer,
}

/*
Draw ICPs are more complex than Dispatch ICPs since they support counts greater than 1 (even indirectly). We thus
need an implementation using Metal's IndirectCommandBuffers (ICBs).

Please note that a MultiDrawDirect implementation without ICBs would require a linear (Theta(n)) number of draw
calls during the command emission; using ICBs moves this work to the GPU, lowering the encoding time. This is however
unoptimal in the case the user encodes one indirect command at a time, where a normal indirect draw would be sufficient
(in a similar manner to how Dispatch ICPs work).

Indirect encoding consists in compute-based approach:
	1. Scratch-allocate one MTL.IndirectCommandBufferExecutionRange from the `buffer.ranges` array at encode-time.
	2. Dispatch a compute thread acquiring an execution range with `count` (directly or indirectly) elements. The
		obtained range gets stored in the previously allocated MTL.IndirectCommandBufferExecutionRange.
		This range acquisition logic is done by atomically updating the `buffer.scratch` state, effectively
		scratch allocating the ICBs buffer at runtime.
		Since the draw call count may not be known at encode-time (i.e. with indirect count), the encode logic
		(step 3) requires a indirect dispatch, whose parameters need to be encoded by this step in
		`buffer.encode_params`.
	3. Dispatch a compute workflow encoding `count` ICB buffers at the previously allocated range (inside
		`buffer.icbs`), translating the gfx arguments into metal ones. This includes the encoding of the draw
		call index into the `buffer.draw_data` buffer.

It is important to note that metal does not expose an equivalent to `gl_DrawID`, so the draw index should be passed
inside a buffer. Such index is encoded in the `buffer.draw_data` buffer.

Indirect draw consists in an `RenderCommandEncoder->executeCommandsInBuffer` call, pointing to the acquired execution
ange indirectly.
*/
_m3_ICP_Draw_Metadata :: struct {
	/*
	Gpu buffer of _m3_Draw_ICP_Gpu_Base_Data. Dynamic data is instanced with:
		- ranges:		[command_count]MTL.IndirectCommandBufferExecutionRange,
		- encode_params:	[command_count]MTL.DispatchThreadgroupsIndirectArguments,
		- draw_data:		[call_count]_m3_Draw_ICP_Call_Data,

	TODO: If we can guarantee that multiple encoding dispatches do not get executed in parallel, we can collapse
		`pool.encode_params` into a single value.
	*/
	buffer: ^MTL.Buffer,

	icbs:	^MTL.IndirectCommandBuffer,

}
_m3_Draw_ICP_Gpu_Base_Data :: struct #packed {
	command_count:	u32,
	call_count:	u32,
	// GPU atomic counter. Points to the first available location in the `buffer.icbs` and the
	//	`buffer.encode_params`buffer.
	index:		u32,
	_pad_0:		u32,

	icbs:		MTL.ResourceID,

	/*
	Contains:
		- ranges:		[command_count]MTL.IndirectCommandBufferExecutionRange,
		- encode_params:	[command_count]MTL.DispatchThreadgroupsIndirectArguments,
		- draw_data:		[call_count]_m3_Draw_ICP_Call_Data,
	*/
	dynamic_data:	[0]u64,
}
#assert(size_of(_m3_Draw_ICP_Gpu_Base_Data) == 24)
#assert(offset_of(_m3_Draw_ICP_Gpu_Base_Data, dynamic_data) == 24)

_m3_Draw_ICP_Call_Data :: struct #packed {
	arguments:	rawptr,
	draw_id:	u16,
	_padding:	[3]u16,
}
#assert(size_of(_m3_Draw_ICP_Call_Data) == 16)

_m3_Indirect_Command_Pool_Metadata :: struct {
	/*
	Keeps track of the cpu-side scratch-allocated indirect arguments.
	Depending on the pool type:
		- Dispatch: Points to the first available location in the `buffer.arguments` array.
		- Draw: Points to the first available location in the `buffer.ranges` array.
	*/
	index: int,

	using archetype: struct #raw_union {
		dispatch:	_m3_ICP_Dispatch_Metadata,
		draw:		_m3_ICP_Draw_Metadata,
	},
}

_m3_Indirect_Command_Metadata :: struct {
	/*
	Depending on the pool type:
		- Dispatch: The cpu-allocated MTL.DispatchThreadgroupsIndirectArguments location in the pool's
			`buffer.arguments` buffer.
		- Draw:	The cpu-allocated MTL.IndirectCommandBufferExecutionRange location in the pool's `buffer.ranges`
			buffer.
	*/
	slot:	int,
}

_m3_encode_dispatch_indirect_pso: ^MTL.ComputePipelineState
_m3_allocate_icb_range_pso: ^MTL.ComputePipelineState
_m3_allocate_icb_range_count_pso: ^MTL.ComputePipelineState
_m3_encode_icbs_draw_pso: ^MTL.ComputePipelineState
_m3_encode_icbs_draw_indexed_pso: ^MTL.ComputePipelineState

_m3_init_indirect :: proc() -> Result {

	compile_internal_compute_kernel :: proc($name: cstring) -> ^MTL.ComputePipelineState {
		function := _m3_internal_shader_library->newFunctionWithName(NS.AT(name))
		if function == nil {
			log.panicf("Could not create the `%s` internal kernel function.", name)
		}
		defer function->release()
		
		pso, pso_err := _m3_device->newComputePipelineStateWithFunction(function)
		if pso_err != nil {
			log.panicf(
				"Could not create the `%s` pipeline state object. Got error `%s`.",
				name,
				pso_err->localizedFailureReason()->odinString(),
			)
		}

		return pso
	}

	_m3_encode_dispatch_indirect_pso	= compile_internal_compute_kernel("encode_dispatch_indirect")
	_m3_allocate_icb_range_pso		= compile_internal_compute_kernel("allocate_icb_range")
	_m3_allocate_icb_range_count_pso	= compile_internal_compute_kernel("allocate_icb_range_count")
	_m3_encode_icbs_draw_pso		= compile_internal_compute_kernel("encode_draw_icbs")
	_m3_encode_icbs_draw_indexed_pso	= compile_internal_compute_kernel("encode_draw_indexed_icbs")
	
	return nil
}

_m3_fini_indirect :: proc() {
	if _m3_encode_dispatch_indirect_pso != nil {
		_m3_encode_dispatch_indirect_pso->release()
	}
	if _m3_allocate_icb_range_pso != nil {
		_m3_allocate_icb_range_pso->release()
	}
	if _m3_allocate_icb_range_count_pso != nil {
		_m3_allocate_icb_range_count_pso->release()
	}
	if _m3_encode_icbs_draw_pso != nil {
		_m3_encode_icbs_draw_pso->release()
	}
	if _m3_encode_icbs_draw_indexed_pso != nil {
		_m3_encode_icbs_draw_indexed_pso->release()
	}
}

_m3_create_indirect_command_pool :: proc(
	metadata:	^_Indirect_Command_Pool_Metadata,
	descriptor:	Indirect_Command_Pool_Descriptor,
) -> Result {

	switch descriptor.type {
	case .Dispatch:
		return _m3_create_dispatch_icp(metadata, descriptor)
	case .Draw:
		return _m3_create_draw_icp(metadata, descriptor)
	}

	unreachable()
}

_m3_create_dispatch_icp :: proc(
	metadata:	^_Indirect_Command_Pool_Metadata,
	descriptor:	Indirect_Command_Pool_Descriptor,
) -> Result {

	gpu_data_size := _m3_size_of_dispatch_icp_gpu_data(descriptor)
	metadata.m3.dispatch.buffer = _m3_device->newBufferWithLength(
		cast(NS.UInteger)gpu_data_size,
		{ .StorageModePrivate, .HazardTrackingModeUntracked },
	)

	if sync.guard(&_m3_residency_set_mutex) {
		_m3_residency_set->addAllocation(metadata.m3.dispatch.buffer)
		_m3_residency_set->commit()
	}

	if metadata.m3.dispatch.buffer == nil {
		return .Out_Of_Gpu_Memory
	}

	return nil
}

/*
The size of the dispatch ICP buffer:
	struct {
		arguments:	[pool.call_count]MTL.DispatchThreadgroupsIndirectArguments,
	}
*/
_m3_size_of_dispatch_icp_gpu_data :: proc(descriptor: Indirect_Command_Pool_Descriptor) -> int {
	return size_of(MTL.DispatchThreadgroupsIndirectArguments) * descriptor.call_count
}


_m3_create_draw_icp :: proc(
	metadata:	^_Indirect_Command_Pool_Metadata,
	descriptor:	Indirect_Command_Pool_Descriptor,
) -> (res: Result) {

	gpu_data_size := _m3_size_of_draw_icp_gpu_data(descriptor)
	metadata.m3.draw.buffer = _m3_device->newBufferWithLength(
		cast(NS.UInteger)gpu_data_size,
		{ .HazardTrackingModeUntracked },
	)

	if metadata.m3.draw.buffer == nil {
		return .Out_Of_Gpu_Memory
	}
	defer if res != nil do metadata.m3.draw.buffer->release()

	icb_descriptor := MTL.IndirectCommandBufferDescriptor.alloc()->init()
	icb_descriptor->autorelease()

	icb_descriptor->setInheritBuffers(false)
	icb_descriptor->setInheritPipelineState(true)
	icb_descriptor->setMaxVertexBufferBindCount(3)
	icb_descriptor->setMaxFragmentBufferBindCount(3)
	icb_descriptor->setCommandTypes({ .Draw, .DrawIndexed })

	metadata.m3.draw.icbs = _m3_device->newIndirectCommandBufferWithDescriptor(
		icb_descriptor,
		cast(NS.UInteger)descriptor.call_count,
		{ .StorageModePrivate, .HazardTrackingModeUntracked },
	)
	if metadata.m3.draw.icbs == nil {
		return .Out_Of_Gpu_Memory
	}

	(cast(^_m3_Draw_ICP_Gpu_Base_Data)metadata.m3.draw.buffer->contents())^ = {
		command_count	= cast(u32)metadata.command_count,
		call_count	= cast(u32)metadata.call_count,
		index		= 0,
		icbs		= metadata.m3.draw.icbs->gpuResourceID(),
	}

	if sync.guard(&_m3_residency_set_mutex) {
		_m3_residency_set->addAllocation(metadata.m3.draw.buffer)
		_m3_residency_set->addAllocation(metadata.m3.draw.icbs)
		_m3_residency_set->commit()
	}

	return nil
}

_m3_size_of_draw_icp_gpu_data :: proc(descriptor: Indirect_Command_Pool_Descriptor) -> int {
	icp_base_size		:= size_of(_m3_Draw_ICP_Gpu_Base_Data)
	ranges_size		:= size_of(MTL.IndirectCommandBufferExecutionRange) * descriptor.command_count
	encode_params_size	:= size_of(MTL.DispatchThreadgroupsIndirectArguments) * descriptor.command_count
	draw_data_size		:= size_of(_m3_Draw_ICP_Call_Data) * descriptor.call_count

	return icp_base_size + ranges_size + encode_params_size + draw_data_size
}

_m3_destroy_indirect_command_pool :: proc(metadata: ^_Indirect_Command_Pool_Metadata) {
	switch metadata.type {
	case .Dispatch:
		metadata.m3.dispatch.buffer->release()

	case .Draw:
		metadata.m3.draw.buffer->release()
		metadata.m3.draw.icbs->release()
	}
}

_m3_prepare_indirect_command :: proc(
	icp_metadata:	^_Indirect_Command_Pool_Metadata,
	ic_metadata:	^_Indirect_Command_Metadata,
) -> Result {
	
	ic_metadata.m3.slot = _m3_icp_scratch_alloc_slot(icp_metadata)

	return nil
}

_m3_icp_scratch_alloc_slot :: proc(icp_metadata: ^_Indirect_Command_Pool_Metadata) -> (slot: int) {
	for {
		old := sync.atomic_load(&icp_metadata.m3.index)
		slot = (old + 1) % icp_metadata.command_count

		_, did_exchange := sync.atomic_compare_exchange_weak(&icp_metadata.m3.index, old, slot)
		if did_exchange {
			break
		}
	}

	return slot
}

_m3_ic_offset_of_indirect_dispatch_args :: proc(ic_metadata: ^_Indirect_Command_Metadata) -> uintptr {
	assert(ic_metadata.type == .Dispatch)
	return size_of(MTL.DispatchThreadgroupsIndirectArguments) * cast(uintptr)ic_metadata.m3.slot
}

_m3_ic_offset_of_indirect_execution_range :: proc(ic_metadata: ^_Indirect_Command_Metadata) -> uintptr {
	assert(ic_metadata.type != .Dispatch)
	return offset_of(_m3_Draw_ICP_Gpu_Base_Data, dynamic_data) +
		size_of(MTL.IndirectCommandBufferExecutionRange) * cast(uintptr)ic_metadata.m3.slot
}

_m3_ic_offset_of_indirect_encode_dispatch_args :: proc(
	icp_metadata:	^_Indirect_Command_Pool_Metadata,
	ic_metadata:	^_Indirect_Command_Metadata,
) -> uintptr {
	assert(icp_metadata.type == .Draw && ic_metadata.type != .Dispatch)
	
	return offset_of(_m3_Draw_ICP_Gpu_Base_Data, dynamic_data) +
		size_of(MTL.IndirectCommandBufferExecutionRange) * cast(uintptr)icp_metadata.command_count +
		size_of(MTL.DispatchThreadgroupsIndirectArguments) * cast(uintptr)ic_metadata.m3.slot
}

_m3_ic_offset_of_indirect_draw_index :: proc(
	icp_metadata:	^_Indirect_Command_Pool_Metadata,
	ic_metadata:	^_Indirect_Command_Metadata,
) -> uintptr {
	assert(icp_metadata.type == .Draw && ic_metadata.type != .Dispatch)

	return offset_of(_m3_Draw_ICP_Gpu_Base_Data, dynamic_data) +
		size_of(MTL.IndirectCommandBufferExecutionRange) * cast(uintptr)icp_metadata.command_count +
		size_of(MTL.DispatchThreadgroupsIndirectArguments) * cast(uintptr)icp_metadata.command_count +
		size_of(_m3_Draw_ICP_Call_Data) * cast(uintptr)ic_metadata.m3.slot
}

_m3_emit_encode_dispatch_indirect :: proc(
	metadata:	^_Command_Buffer_Metadata,
	queue_metadata:	^_Queue_Metadata,
	command:	_Command_Encode_Indirect,
	icp_metadata:	^_Indirect_Command_Pool_Metadata,
	ic_metadata:	^_Indirect_Command_Metadata,
) -> Result {
	assert(ic_metadata.type == .Dispatch)

	_m3_Encode_Dispatch_Indirect_Arguments :: struct #packed {
		// GPU pointer to Dispatch_Indirect_Parameters
		source:		rawptr,
		// GPU pointer to MTL.DispatchThreadgroupsIndirectArguments
		destination:	rawptr,
	}

	destination := cast(uintptr)icp_metadata.m3.dispatch.buffer->gpuAddress() +
		_m3_ic_offset_of_indirect_dispatch_args(ic_metadata)

	arguments := _m3_Encode_Dispatch_Indirect_Arguments{
		source		= ic_metadata.dispatch.indirect_parameters,
		destination	= cast(rawptr)destination,
	}

	_m3_enable_compute_encoder(metadata) or_return

	metadata.m3.compute_encoder->setComputePipelineState(_m3_encode_dispatch_indirect_pso)
	metadata.m3.compute_encoder->setBytes(mem.ptr_to_bytes(&arguments), 0)
	metadata.m3.compute_encoder->dispatchThreadgroups({ 1, 1, 1 }, { 1, 1, 1 })
	
	metadata.m3.bound_compute_pipeline = {}

	return nil
}

_m3_emit_allocate_icb_range :: proc(
	metadata:	^_Command_Buffer_Metadata,
	queue_metadata:	^_Queue_Metadata,
	icp_metadata:	^_Indirect_Command_Pool_Metadata,
	ic_metadata:	^_Indirect_Command_Metadata,
) -> Result {

	_m3_Allocate_ICB_Range_Arguments :: struct #packed {
		// GPU pointer to the root icp buffer (`draw.buffer`)
		pool:		rawptr,
		// GPU pointer to MTL.IndirectCommandBufferExecutionRange
		destination:	rawptr,
		// GPU pointer to MTL.DispatchThreadgroupsIndirectArguments
		encode_icbs_dispatch_params: rawptr,
		count:		u64,
	}

	pool := cast(uintptr)icp_metadata.m3.draw.buffer->gpuAddress()
	destination := pool + _m3_ic_offset_of_indirect_execution_range(ic_metadata)
	encode_icbs_dispatch_params := pool + _m3_ic_offset_of_indirect_encode_dispatch_args(icp_metadata, ic_metadata)

	arguments := _m3_Allocate_ICB_Range_Arguments{
		pool		= cast(rawptr)pool,
		destination	= cast(rawptr)destination,
		encode_icbs_dispatch_params = cast(rawptr)encode_icbs_dispatch_params,
	}

	pipeline: ^MTL.ComputePipelineState
	switch ic_metadata.type {
	case .Draw:
		arguments.count = cast(u64)ic_metadata.draw.count
		pipeline = _m3_allocate_icb_range_pso
	case .Draw_Count:
		arguments.count = cast(u64)cast(uintptr)ic_metadata.draw_count.count
		pipeline = _m3_allocate_icb_range_count_pso
	case .Draw_Indexed:
		arguments.count = cast(u64)ic_metadata.draw_indexed.count
		pipeline = _m3_allocate_icb_range_pso
	case .Draw_Indexed_Count:
		arguments.count = cast(u64)cast(uintptr)ic_metadata.draw_indexed_count.count
		pipeline = _m3_allocate_icb_range_count_pso
	case .Dispatch:
		log.panic("Invalid indirect command type: `.Dispatch` found, while any draw expected.")
	}


	_m3_enable_compute_encoder(metadata) or_return
	metadata.m3.compute_encoder->setComputePipelineState(pipeline)
	metadata.m3.compute_encoder->setBytes(mem.ptr_to_bytes(&arguments), 0)
	metadata.m3.compute_encoder->dispatchThreadgroups({ 1, 1, 1 }, { 1, 1, 1 })

	metadata.m3.bound_compute_pipeline = {}

	return nil
}

_m3_emit_encode_draw_icbs :: proc(
	metadata:	^_Command_Buffer_Metadata,
	queue_metadata:	^_Queue_Metadata,
	command:	_Command_Encode_Indirect,
	icp_metadata:	^_Indirect_Command_Pool_Metadata,
	ic_metadata:	^_Indirect_Command_Metadata,
) -> Result {

	assert(ic_metadata.type == .Draw || ic_metadata.type == .Draw_Count)

	_m3_Encode_Draw_ICBs_Arguments :: struct #packed {
		// GPU pointer to the root icp buffer (`draw.buffer`)
		pool:		rawptr,
		// GPU pointer to MTL.IndirectCommandBufferExecutionRange
		range:		rawptr,
		// GPU pointer to [count]Draw_Indirect_Parameters
		parameters:	rawptr,
		// GPU pointer to the shader argument buffer
		arguments:	rawptr,
		// GPU pointer to the resource-set root buffer
		resource_set:	rawptr,
		primitive:	MTL.PrimitiveType,
	}

	pipeline: Pipeline
	parameters: rawptr
	arguments_ptr: rawptr
	#partial switch ic_metadata.type {
	case .Draw:
		pipeline = ic_metadata.draw.render_pipeline
		parameters = ic_metadata.draw.indirect_parameters
		arguments_ptr = ic_metadata.draw.arguments
	case .Draw_Count:
		pipeline = ic_metadata.draw_count.render_pipeline
		parameters = ic_metadata.draw_count.indirect_parameters
		arguments_ptr = ic_metadata.draw_count.arguments
	}

	pipeline_metadata, pipeline_res := _metadata_of(pipeline)
	_check_internal_emission_result(pipeline_res) or_return

	pool := cast(uintptr)icp_metadata.m3.draw.buffer->gpuAddress()
	range := pool + _m3_ic_offset_of_indirect_execution_range(ic_metadata)
	resource_set_metadata, resource_set_res := _resource_set_metadata_of(metadata.resource_set)
	_check_internal_emission_result(resource_set_res) or_return

	arguments := _m3_Encode_Draw_ICBs_Arguments{
		pool		= cast(rawptr)pool,
		range		= cast(rawptr)range,
		primitive	= _m3_TOPOLOGY_TO_MTL[pipeline_metadata.render.topology],
		parameters	= parameters,
		arguments	= arguments_ptr,
		resource_set	= cast(rawptr)cast(uintptr)resource_set_metadata.m3.root_buffer->gpuAddress(),
	}

	_m3_enable_compute_encoder(metadata) or_return
	metadata.m3.compute_encoder->setComputePipelineState(_m3_encode_icbs_draw_pso)
	metadata.m3.compute_encoder->setBytes(mem.ptr_to_bytes(&arguments), 0)

	encode_icbs_dispatch_params_offset := _m3_ic_offset_of_indirect_encode_dispatch_args(icp_metadata, ic_metadata)
	metadata.m3.compute_encoder->dispatchThreadgroupsWithIndirectBuffer(
		icp_metadata.m3.draw.buffer,
		cast(NS.UInteger)encode_icbs_dispatch_params_offset,
		{ 256, 1, 1 },
	)

	metadata.m3.bound_compute_pipeline = {}

	return nil
}

_m3_emit_encode_draw_indexed_icbs :: proc(
	metadata:	^_Command_Buffer_Metadata,
	queue_metadata:	^_Queue_Metadata,
	command:	_Command_Encode_Indirect,
	icp_metadata:	^_Indirect_Command_Pool_Metadata,
	ic_metadata:	^_Indirect_Command_Metadata,
) -> Result {

	assert(ic_metadata.type == .Draw_Indexed || ic_metadata.type == .Draw_Indexed_Count)

	_m3_Encode_Draw_ICBs_Arguments :: struct #packed {
		// GPU pointer to the root icp buffer (`draw.buffer`)
		pool:		rawptr,
		// GPU pointer to MTL.IndirectCommandBufferExecutionRange
		range:		rawptr,
		// GPU pointer to [count]Draw_Indexed_Indirect_Parameters
		parameters:	rawptr,
		// GPU pointer to the shader argument buffer
		arguments:	rawptr,
		// GPU pointer to the resource-set root buffer
		resource_set:	rawptr,
		indices:	rawptr,
		primitive:	MTL.PrimitiveType,
		index_type:	bool,
	}

	pipeline: Pipeline
	parameters: rawptr
	arguments_ptr: rawptr
	indices: rawptr
	index_type: Index_Type
	#partial switch ic_metadata.type {
	case .Draw_Indexed:
		pipeline	= ic_metadata.draw_indexed.render_pipeline
		parameters	= ic_metadata.draw_indexed.indirect_parameters
		arguments_ptr = ic_metadata.draw_indexed.arguments
		indices		= ic_metadata.draw_indexed.indices
		index_type	= ic_metadata.draw_indexed.index_type
	case .Draw_Indexed_Count:
		pipeline	= ic_metadata.draw_indexed_count.render_pipeline
		parameters	= ic_metadata.draw_indexed_count.indirect_parameters
		arguments_ptr = ic_metadata.draw_indexed_count.arguments
		indices		= ic_metadata.draw_indexed_count.indices
		index_type	= ic_metadata.draw_indexed.index_type
	}

	pipeline_metadata, pipeline_res := _metadata_of(pipeline)
	_check_internal_emission_result(pipeline_res) or_return

	pool := cast(uintptr)icp_metadata.m3.draw.buffer->gpuAddress()
	range := pool + _m3_ic_offset_of_indirect_execution_range(ic_metadata)
	resource_set_metadata, resource_set_res := _resource_set_metadata_of(metadata.resource_set)
	_check_internal_emission_result(resource_set_res) or_return

	arguments := _m3_Encode_Draw_ICBs_Arguments{
		pool		= cast(rawptr)pool,
		range		= cast(rawptr)range,
		parameters	= parameters,
		arguments	= arguments_ptr,
		resource_set	= cast(rawptr)cast(uintptr)resource_set_metadata.m3.root_buffer->gpuAddress(),
		indices		= indices,
		primitive	= _m3_TOPOLOGY_TO_MTL[pipeline_metadata.render.topology],
		index_type	= index_type == .U32,
	}

	_m3_enable_compute_encoder(metadata) or_return
	metadata.m3.compute_encoder->setComputePipelineState(_m3_encode_icbs_draw_indexed_pso)
	metadata.m3.compute_encoder->setBytes(mem.ptr_to_bytes(&arguments), 0)

	encode_icbs_dispatch_params_offset := _m3_ic_offset_of_indirect_encode_dispatch_args(icp_metadata, ic_metadata)
	metadata.m3.compute_encoder->dispatchThreadgroupsWithIndirectBuffer(
		icp_metadata.m3.draw.buffer,
		cast(NS.UInteger)encode_icbs_dispatch_params_offset,
		{ 256, 1, 1 },
	)

	metadata.m3.bound_compute_pipeline = {}

	return nil
}

_m3_emit_encode_draw_indirect :: proc(
	metadata:	^_Command_Buffer_Metadata,
	queue_metadata:	^_Queue_Metadata,
	command:	_Command_Encode_Indirect,
	icp_metadata:	^_Indirect_Command_Pool_Metadata,
	ic_metadata:	^_Indirect_Command_Metadata,
) -> Result {
	assert(ic_metadata.type == .Draw || ic_metadata.type == .Draw_Count)

	_m3_emit_allocate_icb_range(metadata, queue_metadata, icp_metadata, ic_metadata) or_return
	_m3_flush_encoder(metadata, true)
	_m3_emit_encode_draw_icbs(metadata, queue_metadata, command, icp_metadata, ic_metadata) or_return

	return nil
}

_m3_emit_encode_draw_indexed_indirect :: proc(
	metadata:	^_Command_Buffer_Metadata,
	queue_metadata:	^_Queue_Metadata,
	command:	_Command_Encode_Indirect,
	icp_metadata:	^_Indirect_Command_Pool_Metadata,
	ic_metadata:	^_Indirect_Command_Metadata,
) -> Result {
	assert(ic_metadata.type == .Draw_Indexed || ic_metadata.type == .Draw_Indexed_Count)

	_m3_emit_allocate_icb_range(metadata, queue_metadata, icp_metadata, ic_metadata) or_return
	_m3_flush_encoder(metadata, true)
	_m3_emit_encode_draw_indexed_icbs(metadata, queue_metadata, command, icp_metadata, ic_metadata) or_return

	return nil
}

_m3_emit_encode_indirect :: proc(
	metadata:	^_Command_Buffer_Metadata,
	queue_metadata:	^_Queue_Metadata,
	command:	_Command_Encode_Indirect,
) -> Result {
	ic_metadata, ic_result := _metadata_of(command.command)
	_check_internal_emission_result(ic_result) or_return

	icp_metadata, icp_result := _metadata_of(ic_metadata.pool)
	_check_internal_emission_result(icp_result) or_return

	#partial switch ic_metadata.type {
	case .Dispatch:
		_m3_emit_encode_dispatch_indirect(metadata, queue_metadata, command, icp_metadata, ic_metadata) or_return
	case .Draw, .Draw_Count:
		_m3_emit_encode_draw_indirect(metadata, queue_metadata, command, icp_metadata, ic_metadata) or_return
	case .Draw_Indexed, .Draw_Indexed_Count:
		_m3_emit_encode_draw_indexed_indirect(metadata, queue_metadata, command, icp_metadata, ic_metadata) or_return
	}

	return nil
}

_m3_emit_execute_indirect :: proc(
	metadata:	^_Command_Buffer_Metadata,
	queue_metadata:	^_Queue_Metadata,
	command:	_Command_Execute_Indirect,
) -> Result {

	ic_metadata, ic_result := _metadata_of(command.command)
	_check_internal_emission_result(ic_result) or_return

	icp_metadata, icp_result := _metadata_of(ic_metadata.pool)
	_check_internal_emission_result(icp_result) or_return

	#partial switch ic_metadata.type {
	case .Dispatch:
		pipeline_metadata, pipeline_res := _metadata_of(ic_metadata.dispatch.compute_pipeline)
		_check_internal_emission_result(pipeline_res) or_return

		_m3_enable_compute_encoder(metadata) or_return
		_m3_bind_resource_set(metadata, command.resource_set) or_return
		_m3_bind_compute_pipeline(metadata, ic_metadata.dispatch.compute_pipeline)
		metadata.m3.compute_encoder->setBytes(
			mem.byte_slice(&ic_metadata.dispatch.arguments, size_of(ic_metadata.dispatch.arguments)),
			0,
		)
		metadata.m3.compute_encoder->dispatchThreadgroupsWithIndirectBuffer(
			icp_metadata.m3.dispatch.buffer,
			cast(NS.UInteger)_m3_ic_offset_of_indirect_dispatch_args(ic_metadata),
			_m3_size_to_mtl(pipeline_metadata.compute.group_size),
		)

	// NOTE: ic_metadata.draw == ic_metadata.draw_count for the accessed fields. This should be fine.
	case .Draw, .Draw_Count:
		assert(metadata.m3.current_encoder == .Render)

		arguments_ptr := ic_metadata.draw.arguments

		_m3_bind_resource_set(metadata, command.resource_set) or_return
		_m3_bind_depth_stencil(metadata, command.depth_stencil_state) or_return
		_m3_bind_render_pipeline(metadata, ic_metadata.draw.render_pipeline) or_return
		_m3_bind_blend_constant(metadata, command.blend_constant) or_return
		_m3_bind_scissor(metadata, command.scissor) or_return
		metadata.m3.render_encoder->setVertexBytes(mem.byte_slice(&arguments_ptr, size_of(arguments_ptr)), 0)
		metadata.m3.render_encoder->setFragmentBytes(mem.byte_slice(&arguments_ptr, size_of(arguments_ptr)), 0)
		metadata.m3.render_encoder->executeCommandsInBuffer(
			icp_metadata.m3.draw.icbs,
			icp_metadata.m3.draw.buffer,
			cast(NS.UInteger)_m3_ic_offset_of_indirect_execution_range(ic_metadata),
		)

	// NOTE: ic_metadata.draw_indexed == ic_metadata.draw_indexed_count for the accessed fields. This should be fine.
	case .Draw_Indexed, .Draw_Indexed_Count:
		assert(metadata.m3.current_encoder == .Render)

		arguments_ptr := ic_metadata.draw_indexed.arguments

		_m3_bind_resource_set(metadata, command.resource_set) or_return
		_m3_bind_depth_stencil(metadata, command.depth_stencil_state) or_return
		_m3_bind_render_pipeline(metadata, ic_metadata.draw_indexed.render_pipeline) or_return
		_m3_bind_blend_constant(metadata, command.blend_constant) or_return
		_m3_bind_scissor(metadata, command.scissor) or_return
		metadata.m3.render_encoder->setVertexBytes(mem.byte_slice(&arguments_ptr, size_of(arguments_ptr)), 0)
		metadata.m3.render_encoder->setFragmentBytes(mem.byte_slice(&arguments_ptr, size_of(arguments_ptr)), 0)
		metadata.m3.render_encoder->executeCommandsInBuffer(
			icp_metadata.m3.draw.icbs,
			icp_metadata.m3.draw.buffer,
			cast(NS.UInteger)_m3_ic_offset_of_indirect_execution_range(ic_metadata),
		)
	}

	return nil
}
