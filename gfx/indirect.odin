package vicixdev_gfx

/*
Copyright (c) 2026 Vicix (https://github.com/vicixdev)

This Source Code Form is subject to the terms of the Mozilla Public
License, v. 2.0. If a copy of the MPL was not distributed with this
file, You can obtain one at https://mozilla.org/MPL/2.0/.
*/

import "base:runtime"
import "core:sync"
import hm "core:container/handle_map"

Command_Pool_Type :: enum {
	Dispatch,
	Draw,
}

// Denotes the lifetime of the `Indirect_Command` object. It is not related to the underlying memory of the backing
// pool, which uses ring-allocation rules. The user is responsible of ensuring that the referenced memory remains valid.
Indirect_Command_Lifetime :: enum {
	// Gets automatically released after the command gets dispatched. Cannot be used multiple times. Can be used
	// over multiple command buffers.
	One_Shot,
	// Gets automatically released at the end of the command buffer in which it was encoded. Cannot be used across
	// command buffers.
	Command_Buffer,
	// The user must manually release the command via `destroy_indirect_command`. The command can be used multiple
	// times over different command buffers.
	Manual,
}

Indirect_Command_Pool_Descriptor :: struct {
	type:		Command_Pool_Type,

	// TODO: Explain this better

	// The maximum count of Indirect_Command that the pool can hold at the same time.
	// NOTE: This is cpu-side
	command_count:	int,

	// The maximum count of indirect parameters that the pool can hold at the same time.
	// One indirect command can express a command that uses multiple parameters (count > 1).
	// If `type == .Dispatch`, then `command_count == call_count`, since MultiDispatchIndirect isn't supported.
	// `call_count >= command_count`
	// NOTE: This is gpu-side
	call_count:	int,
}

Indirect_Command_Pool :: distinct Handle
_Indirect_Command_Pool_Metadata :: struct {
	handle:		Indirect_Command_Pool,
	using descriptor: Indirect_Command_Pool_Descriptor,

	using platform: struct #raw_union {
		vk: _vk_Indirect_Command_Pool_Metadata,
		m3: _m3_Indirect_Command_Pool_Metadata,
	},
}
_indirect_command_pools:	hm.Dynamic_Handle_Map(_Indirect_Command_Pool_Metadata, Indirect_Command_Pool)
_indirect_command_pools_mutex:	sync.RW_Mutex

_Indirect_Command_Type :: enum {
	Dispatch,
	Draw,
	Draw_Count,
	Draw_Indexed,
	Draw_Indexed_Count,
}
_Dispatch_Indirect_Command_Metadata :: struct {
	compute_pipeline:	Pipeline,
	arguments:		rawptr,
	indirect_parameters:	rawptr,
}
_Draw_Indirect_Command_Metadata :: struct {
	render_pipeline:	Pipeline,
	arguments:		rawptr,
	indirect_parameters:	rawptr,
	count:			int,
}
_Draw_Count_Indirect_Command_Metadata :: struct {
	render_pipeline:	Pipeline,
	arguments:		rawptr,
	indirect_parameters:	rawptr,
	count:			rawptr,
}
_Draw_Indexed_Indirect_Command_Metadata :: struct {
	render_pipeline:	Pipeline,
	arguments:		rawptr,
	indices:		rawptr,
	indirect_parameters:	rawptr,
	count:			int,
	index_type:		Index_Type,
}
_Draw_Indexed_Count_Indirect_Command_Metadata :: struct {
	render_pipeline:	Pipeline,
	arguments:		rawptr,
	indices:		rawptr,
	indirect_parameters:	rawptr,
	count:			rawptr,
	index_type:		Index_Type,
}

Indirect_Command :: distinct Handle
_Indirect_Command_Metadata :: struct {
	handle:		Indirect_Command,
	lifetime:	Indirect_Command_Lifetime,
	// If `lifetime == .One_Shot`, it enforces that the indirect command does not get used more than once.
	used:		bool,

	pool:		Indirect_Command_Pool,

	type:		_Indirect_Command_Type,
	using payload: struct #raw_union {
		dispatch:	_Dispatch_Indirect_Command_Metadata,
		draw:		_Draw_Indirect_Command_Metadata,
		draw_count:	_Draw_Count_Indirect_Command_Metadata,
		draw_indexed:	_Draw_Indexed_Indirect_Command_Metadata,
		draw_indexed_count: _Draw_Indexed_Count_Indirect_Command_Metadata,
	},

	using platform: struct #raw_union {
		vk: struct {},
		m3: _m3_Indirect_Command_Metadata,
	},
}
_indirect_commands:		hm.Dynamic_Handle_Map(_Indirect_Command_Metadata, Indirect_Command)
_indirect_commands_mutex:	sync.RW_Mutex

_init_indirect :: proc() -> Result {
	when TARGET_API == .Vulkan {
		unimplemented()
	} else when TARGET_API == .Metal_3 {
		return _m3_init_indirect()
	}
}
_fini_indirect :: proc() {}

create_indirect_command_pool :: proc(
	descriptor:	Indirect_Command_Pool_Descriptor,
	location :=	#caller_location,
) -> (pool: Indirect_Command_Pool, res: Result) {

	descriptor := descriptor
	_normalize_icp_descriptor(&descriptor)

	_vl_create_indirect_command_pool(descriptor, location) or_return

	handle, metadata := _add_indirect_command_pool_metadata() or_return
	metadata.descriptor = descriptor

	when TARGET_API == .Vulkan {
		res = _vk_create_indirect_command_pool(metadata, descriptor)
	} else when TARGET_API == .Metal_3 {
		res = _m3_create_indirect_command_pool(metadata, descriptor)
	}

	_check_generic_backend_error(res, location) or_return

	return handle, nil
}

destroy_indirect_command_pool :: proc(pool: Indirect_Command_Pool) {
	metadata, metadata_res := _metadata_of(pool)
	if metadata_res != nil do return

	when TARGET_API == .Vulkan {
		_vk_destroy_indirect_command_pool(metadata)
	} else when TARGET_API == .Metal_3 {
		_m3_destroy_indirect_command_pool(metadata)
	}

	_remove_indirect_command_pool_metadata(pool)
}

destroy_indirect_command :: proc(command: Indirect_Command, location := #caller_location) {
	_vl_destroy_indirect_command(command, location)

	_destroy_indirect_command(command)
}

// Skip lifetime checks
_destroy_indirect_command :: proc(command: Indirect_Command) {
	_remove_indirect_command_metadata(command)
}

// Indirect_Commands are allocated following ring-allocation rules:
//	- Their memory is valid until it gets ovewritten by following allocations
//	- The Indirect_Command object itself follows the rules specified by the `Indirect_Command_Lifetime` enum.
// Command Encoding emplace a `.Indirect_Encode` phase into the command buffer.

Dispatch_Indirect_Parameters :: struct {
	group_count:		[3]int,
}
// parameters is a GVA pointing to `Dispatch_Indirect_Parameters`.
encode_dispatch_indirect :: proc(
	command_buffer:		Command_Buffer,
	command_pool:		Indirect_Command_Pool,
	compute_pipeline:	Pipeline,
	arguments:		rawptr,
	indirect_parameters:	rawptr,
	lifetime :=		Indirect_Command_Lifetime.One_Shot,
	location :=		#caller_location,
) -> (_indirect_command: Indirect_Command, res: Result) {

	cb_metadata, cb_result := _metadata_of(command_buffer)
	_check_command_buffer_handle(cb_result, command_buffer, location) or_return

	icp_metadata, icp_result := _metadata_of(command_pool)
	_check_indirect_command_pool_handle(icp_result, command_pool, location) or_return

	_vl_encode_dispatch_indirect(cb_metadata, icp_metadata, arguments, indirect_parameters, location) or_return

	ic_handle, ic_metadata := _add_indirect_command_metadata() or_return
	defer if res != nil do _remove_indirect_command_metadata(ic_handle)

	ic_metadata.pool = command_pool
	ic_metadata.type = .Dispatch
	ic_metadata.lifetime = lifetime
	ic_metadata.dispatch = {
		compute_pipeline	= compute_pipeline,
		arguments		= arguments,
		indirect_parameters	= indirect_parameters,
	}

	when TARGET_API == .Vulkan {
		_vk_prepare_indirect_command(icp_metadata, ic_metadata) or_return
	} else when TARGET_API == .Metal_3 {
		_m3_prepare_indirect_command(icp_metadata, ic_metadata) or_return
	}

	command := _Command_Encode_Indirect{
		command = ic_handle,
	}
	append(&cb_metadata.commands, command) or_return

	_handle_indirect_command_lifetime_at_encoding(cb_metadata, ic_metadata)

	return ic_handle, nil
}

Draw_Indirect_Parameters :: struct {
	vertex_count:		int,
	instance_count:		int,
	base_vertex:		int,
}

// parameter is a GVA poiting to `[count]Draw_Indirect_Parameters`
encode_draw_indirect :: proc(
	command_buffer: 	Command_Buffer,
	command_pool:		Indirect_Command_Pool,
	render_pipeline:	Pipeline,
	arguments:		rawptr,
	indirect_parameters:	rawptr,
	count :=		1,
	lifetime :=		Indirect_Command_Lifetime.One_Shot,
	location :=		#caller_location,
) -> (_indirect_command: Indirect_Command, res: Result) {

	cb_metadata, cb_result := _metadata_of(command_buffer)
	_check_command_buffer_handle(cb_result, command_buffer, location) or_return

	icp_metadata, icp_result := _metadata_of(command_pool)
	_check_indirect_command_pool_handle(icp_result, command_pool, location) or_return

	_vl_encode_draw_indirect(
		cb_metadata, icp_metadata, render_pipeline, arguments, indirect_parameters, count, location) or_return

	ic_handle, ic_metadata := _add_indirect_command_metadata() or_return
	defer if res != nil do _remove_indirect_command_metadata(ic_handle)

	ic_metadata.pool = command_pool
	ic_metadata.type = .Draw
	ic_metadata.lifetime = lifetime
	ic_metadata.draw = {
		render_pipeline = render_pipeline,
		arguments	= arguments,
		indirect_parameters = indirect_parameters,
		count		= count,
	}

	when TARGET_API == .Vulkan {
		_vk_prepare_indirect_command(icp_metadata, ic_metadata) or_return
	} else when TARGET_API == .Metal_3 {
		_m3_prepare_indirect_command(icp_metadata, ic_metadata) or_return
	}

	command := _Command_Encode_Indirect{
		command = ic_handle,
	}
	append(&cb_metadata.commands, command) or_return

	_handle_indirect_command_lifetime_at_encoding(cb_metadata, ic_metadata)
	
	return ic_handle, nil
}

// count is a GVA pointing to `uint`
// parameter is a GVA poiting to `[count^]Draw_Indirect_Parameters`
encode_draw_indirect_count :: proc(
	command_buffer: 	Command_Buffer,
	command_pool:		Indirect_Command_Pool,
	render_pipeline:	Pipeline,
	arguments:		rawptr,
	indirect_parameters:	rawptr,
	count:			rawptr,
	lifetime :=		Indirect_Command_Lifetime.One_Shot,
	location :=		#caller_location,
) -> (_indirect_command: Indirect_Command, res: Result) {

	cb_metadata, cb_result := _metadata_of(command_buffer)
	_check_command_buffer_handle(cb_result, command_buffer, location) or_return

	icp_metadata, icp_result := _metadata_of(command_pool)
	_check_indirect_command_pool_handle(icp_result, command_pool, location) or_return

	_vl_encode_draw_indirect_count(
		cb_metadata, icp_metadata, render_pipeline, arguments, indirect_parameters, count, location) or_return

	ic_handle, ic_metadata := _add_indirect_command_metadata() or_return
	defer if res != nil do _remove_indirect_command_metadata(ic_handle)

	ic_metadata.pool = command_pool
	ic_metadata.type = .Draw_Count
	ic_metadata.lifetime = lifetime
	ic_metadata.draw_count = {
		render_pipeline = render_pipeline,
		arguments	= arguments,
		indirect_parameters = indirect_parameters,
		count		= count,
	}

	when TARGET_API == .Vulkan {
		_vk_prepare_indirect_command(icp_metadata, ic_metadata) or_return
	} else when TARGET_API == .Metal_3 {
		_m3_prepare_indirect_command(icp_metadata, ic_metadata) or_return
	}

	command := _Command_Encode_Indirect{
		command = ic_handle,
	}
	append(&cb_metadata.commands, command) or_return

	_handle_indirect_command_lifetime_at_encoding(cb_metadata, ic_metadata)
	
	return ic_handle, nil
}

Draw_Indexed_Indirect_Parameters :: struct {
	index_count:		int,
	instance_count:		int,
	base_index:		int,
}
// parameter is a GVA poiting to `[count]Draw_Indexed_Indirect_Parameters`
encode_draw_indexed_indirect :: proc(
	command_buffer:		Command_Buffer,
	command_pool:		Indirect_Command_Pool,
	render_pipeline:	Pipeline,
	arguments:		rawptr,
	indices:		rawptr,
	indirect_parameters:	rawptr,
	count :=		1,
	index_type :=		Index_Type.U16,
	lifetime :=		Indirect_Command_Lifetime.One_Shot,
	location :=		#caller_location,
) -> (_indirect_command: Indirect_Command, res: Result) {

	cb_metadata, cb_result := _metadata_of(command_buffer)
	_check_command_buffer_handle(cb_result, command_buffer, location) or_return

	icp_metadata, icp_result := _metadata_of(command_pool)
	_check_indirect_command_pool_handle(icp_result, command_pool, location) or_return

	_vl_encode_draw_indexed_indirect(
		cb_metadata,
		icp_metadata,
		render_pipeline,
		arguments,
		indices,
		indirect_parameters,
		count,
		location,
	) or_return

	ic_handle, ic_metadata := _add_indirect_command_metadata() or_return
	defer if res != nil do _remove_indirect_command_metadata(ic_handle)

	ic_metadata.pool = command_pool
	ic_metadata.type = .Draw_Indexed
	ic_metadata.lifetime = lifetime
	ic_metadata.draw_indexed = {
		render_pipeline = render_pipeline,
		arguments	= arguments,
		indices		= indices,
		indirect_parameters = indirect_parameters,
		count		= count,
		index_type	= index_type,
	}

	when TARGET_API == .Vulkan {
		_vk_prepare_indirect_command(icp_metadata, ic_metadata) or_return
	} else when TARGET_API == .Metal_3 {
		_m3_prepare_indirect_command(icp_metadata, ic_metadata) or_return
	}

	command := _Command_Encode_Indirect{
		command = ic_handle,
	}
	append(&cb_metadata.commands, command) or_return

	_handle_indirect_command_lifetime_at_encoding(cb_metadata, ic_metadata)
	
	return ic_handle, nil
}

// count is a GVA pointing to `uint`
// parameter is a GVA poiting to `[count^]Draw_Indexed_Indirect_Parameters`
encode_draw_indexed_indirect_count :: proc(
	command_buffer:		Command_Buffer,
	command_pool:		Indirect_Command_Pool,
	render_pipeline:	Pipeline,
	arguments:		rawptr,
	indices:		rawptr,
	indirect_parameters:	rawptr,
	count:			rawptr,
	index_type :=		Index_Type.U16,
	lifetime :=		Indirect_Command_Lifetime.One_Shot,
	location :=		#caller_location,
) -> (_indirect_command: Indirect_Command, res: Result) {

	cb_metadata, cb_result := _metadata_of(command_buffer)
	_check_command_buffer_handle(cb_result, command_buffer, location) or_return

	icp_metadata, icp_result := _metadata_of(command_pool)
	_check_indirect_command_pool_handle(icp_result, command_pool, location) or_return

	_vl_encode_draw_indexed_indirect_count(
		cb_metadata,
		icp_metadata,
		render_pipeline,
		arguments,
		indices,
		indirect_parameters,
		count,
		location,
	) or_return

	ic_handle, ic_metadata := _add_indirect_command_metadata() or_return
	defer if res != nil do _remove_indirect_command_metadata(ic_handle)

	ic_metadata.pool = command_pool
	ic_metadata.type = .Draw_Indexed_Count
	ic_metadata.lifetime = lifetime
	ic_metadata.draw_indexed_count = {
		render_pipeline = render_pipeline,
		arguments	= arguments,
		indices		= indices,
		indirect_parameters = indirect_parameters,
		count		= count,
		index_type	= index_type,
	}

	when TARGET_API == .Vulkan {
		_vk_prepare_indirect_command(icp_metadata, ic_metadata) or_return
	} else when TARGET_API == .Metal_3 {
		_m3_prepare_indirect_command(icp_metadata, ic_metadata) or_return
	}

	command := _Command_Encode_Indirect{
		command = ic_handle,
	}
	append(&cb_metadata.commands, command) or_return

	_handle_indirect_command_lifetime_at_encoding(cb_metadata, ic_metadata)
	
	return ic_handle, nil
}

execute_indirect :: proc(
	command_buffer:		Command_Buffer,
	indirect_command:	Indirect_Command,
	location :=		#caller_location,
) -> Result {

	cb_metadata, cb_result := _metadata_of(command_buffer)
	_check_command_buffer_handle(cb_result, command_buffer, location) or_return

	ic_metadata, ic_result := _metadata_of(indirect_command)
	_check_indirect_command_handle(ic_result, indirect_command, location) or_return

	command := _Command_Execute_Indirect{
		command		= indirect_command,
		resource_set	= cb_metadata.resource_set,
		depth_stencil_state = cb_metadata.depth_stencil_state,
		blend_constant	= cb_metadata.blend_constant,
		scissor		= cb_metadata.scissor,
	}
	append(&cb_metadata.commands, command) or_return

	_handle_indirect_command_lifetime_at_execution(cb_metadata, ic_metadata)

	return nil
}

_normalize_icp_descriptor :: proc(descriptor: ^Indirect_Command_Pool_Descriptor) {
	if descriptor.call_count == 0 && descriptor.command_count != 0 {
		descriptor.call_count = descriptor.command_count
	} else if descriptor.call_count != 0 && descriptor.command_count == 0 {
		descriptor.command_count = descriptor.call_count
	}
}

_vl_create_indirect_command_pool :: proc(
	descriptor:	Indirect_Command_Pool_Descriptor,
	location:	runtime.Source_Code_Location,
) -> Result {
	when !ENABLE_VALIDATION do return nil

	_check_condition(
		_impl(descriptor.type == .Dispatch, descriptor.call_count == descriptor.command_count),
		.Invalid_Descriptor,
		.Error,
		"Invalid descriptor",
		"Incompatible call and command count: dispatch indirect command pools do not support indirect " +
		"command count, thus `descriptor.command_count` (%d) must be equal to `descriptor.call_count` (%d).",
		descriptor.command_count,
		descriptor.call_count,
		location=location,
	) or_return
	_check_condition(
		descriptor.call_count >= descriptor.command_count,
		.Invalid_Descriptor,
		.Error,
		"Invalid descriptor",
		"Incompatible call and command count: `descriptor.call_count` (%d) must be greater or equal to " +
		"`descriptor.command_count` (%d).",
		descriptor.call_count,
		descriptor.command_count,
		location=location,
	) or_return
	_check_condition(
		descriptor.call_count > 0,
		.Invalid_Descriptor,
		.Error,
		"Invalid descriptor",
		"Invalid call count: `descriptor.call_count` must be greater than 0.",
		location=location,
	) or_return
	_check_condition(
		descriptor.command_count > 0,
		.Invalid_Descriptor,
		.Error,
		"Invalid descriptor",
		"Invalid command count: `descriptor.command_count` must be greater than 0.",
		location=location,
	) or_return
 
	return nil
}

_vl_destroy_indirect_command :: proc(command: Indirect_Command, location: runtime.Source_Code_Location) -> Result {
	when !ENABLE_VALIDATION do return nil

	metadata := _metadata_of(command) or_return

	_check_condition(
		metadata.lifetime == .Manual,
		.Invalid_Indirect_Command_Lifetime,
		.Error,
		"Invalid indirect command lifetime",
		"Only indirect commands with lifetime `.Manual` can be manually destroyed. Found lifetime `.%v` " +
		"instead. Please note that `.One_Shot` commands gets automatically destroyed upon use, while " +
		"`.Command_Buffer` gets released after the command buffer in which it got encoded gets submitted.",
		metadata.lifetime,
		location=location,
	) or_return
	_check_generic_condition(
		metadata.used,
		.Warning,
		"Unused command freed",
		"The indirect command `%v` is being destroyed whilst it wasn't yet executed.",
		command,
		location=location,
	)

	return nil
}

_vl_encode_indirect_base :: proc(
	cb_metadata:		^_Command_Buffer_Metadata,
	location:		runtime.Source_Code_Location,
) -> Result {
	_check_condition(
		!cb_metadata.is_encoding_render_pass,
		.Incompatible_Command_Buffer_Stage,
		.Error,
		"Encoding during renderpass.",
		"It is not possible to encode indirect arguments during a renderpass. Please encode them outside, " +
		"while using a barrier waiting for the `.Encode_Indirect` stage.",
		location=location,
	) or_return
 
	return nil
}

_vl_encode_dispatch_indirect :: proc(
	cb_metadata:		^_Command_Buffer_Metadata,
	icp_metadata:		^_Indirect_Command_Pool_Metadata,
	arguments:		rawptr,
	indirect_parameters:	rawptr,
	location:		runtime.Source_Code_Location,
) -> Result {
	when !ENABLE_VALIDATION do return nil

	_vl_encode_indirect_base(cb_metadata, location) or_return

	_check_condition(
		icp_metadata.type == .Dispatch,
		.Incompatible_Indirect_Command_Pool,
		.Error,
		"Incompatible indirect command pool",
		"Could not encode a dispatch command into the provided command pool `%v`: the command pool is not of " +
		"type `.Dispatch`.",
		icp_metadata.handle,
		location=location,
	)

	arguments_info, arguments_res := _address_info_of(arguments)
	_check_address_info(arguments_res, arguments, location) or_return
	_check_gpu_address(arguments_info, location) or_return

	indirect_parameters_info, indirect_parameters_res := _address_info_of(indirect_parameters)
	_check_address_info(indirect_parameters_res, indirect_parameters, location) or_return
	_check_gpu_address(indirect_parameters_info, location) or_return
 
	return nil
}

_vl_encode_draw_indirect_base :: proc(
	icp_metadata:		^_Indirect_Command_Pool_Metadata,
	pipeline:		Pipeline,
	arguments:		rawptr,
	indirect_parameters:	rawptr,
	location:		runtime.Source_Code_Location,
) -> Result {

	_check_condition(
		icp_metadata.type == .Draw,
		.Incompatible_Indirect_Command_Pool,
		.Error,
		"Incompatible indirect command pool",
		"Could not encode a draw command into the provided command pool `%v`: the command pool is not of type" +
		"`.Draw`.",
		icp_metadata.handle,
		location=location,
	) or_return

	pipeline_metadata, pipeline_res := _metadata_of(pipeline)
	_check_pipeline_handle(pipeline_res, pipeline, location) or_return
	_check_condition(
		pipeline_metadata.type == .Render,
		.Incompatible_Pipeline,
		.Error,
		"Incompatible pipeline",
		"The provided pipeline `%v` is not a render pipeline.",
		pipeline_metadata.handle,
		location=location,
	) or_return

	arguments_info, arguments_res := _address_info_of(arguments)
	_check_address_info(arguments_res, arguments, location) or_return
	_check_gpu_address(arguments_info, location) or_return

	indirect_parameters_info, indirect_parameters_res := _address_info_of(indirect_parameters)
	_check_address_info(indirect_parameters_res, indirect_parameters, location) or_return
	_check_gpu_address(indirect_parameters_info, location) or_return
 	
	return nil
}

_vl_encode_draw_indirect :: proc(
	cb_metadata:		^_Command_Buffer_Metadata,
	icp_metadata:		^_Indirect_Command_Pool_Metadata,
	pipeline:		Pipeline,
	arguments:		rawptr,
	indirect_parameters:	rawptr,
	count:			int,
	location:		runtime.Source_Code_Location,
) -> Result {
	when !ENABLE_VALIDATION do return nil

	_vl_encode_indirect_base(cb_metadata, location) or_return
	_vl_encode_draw_indirect_base(icp_metadata, pipeline, arguments, indirect_parameters, location) or_return

	_check_condition(
		count >= 0,
		.Invalid_Arguments,
		.Error,
		"Invalid indirect count",
		"The `count` parameter cannot be negative. Count `%d` found.",
		count,
		location=location,
	)
	_check_condition(
		count <= icp_metadata.call_count,
		.Invalid_Arguments,
		.Error,
		"Invalid indirect count",
		"The `count` parameter (%d) cannot greater than the indirect command pool call count (%d).",
		count,
		icp_metadata.call_count,
		location=location,
	)
 	
	return nil
}

_vl_encode_draw_indirect_count :: proc(
	cb_metadata:		^_Command_Buffer_Metadata,
	icp_metadata:		^_Indirect_Command_Pool_Metadata,
	pipeline:		Pipeline,
	arguments:		rawptr,
	indirect_parameters:	rawptr,
	count:			rawptr,
	location:		runtime.Source_Code_Location,
) -> Result {
	when !ENABLE_VALIDATION do return nil

	_vl_encode_indirect_base(cb_metadata, location) or_return
	_vl_encode_draw_indirect_base(icp_metadata, pipeline, arguments, indirect_parameters, location) or_return

	count_info, count_res := _address_info_of(count)
	_check_address_info(count_res, count, location) or_return
	_check_gpu_address(count_info, location) or_return

	return nil
}

_vl_encode_draw_indexed_indirect_base :: proc(
	icp_metadata:		^_Indirect_Command_Pool_Metadata,
	pipeline:		Pipeline,
	arguments:		rawptr,
	indirect_parameters:	rawptr,
	indices:		rawptr,
	location:		runtime.Source_Code_Location,
) -> Result {

	_check_condition(
		icp_metadata.type == .Draw,
		.Incompatible_Indirect_Command_Pool,
		.Error,
		"Incompatible indirect command pool",
		"Could not encode a draw command into the provided command pool `%v`: the command pool is not of type" +
		"`.Draw`.",
		icp_metadata.handle,
		location=location,
	) or_return

	pipeline_metadata, pipeline_res := _metadata_of(pipeline)
	_check_pipeline_handle(pipeline_res, pipeline, location) or_return
	_check_condition(
		pipeline_metadata.type == .Render,
		.Incompatible_Pipeline,
		.Error,
		"Incompatible pipeline",
		"The provided pipeline `%v` is not a render pipeline.",
		pipeline_metadata.handle,
		location=location,
	) or_return

	arguments_info, arguments_res := _address_info_of(arguments)
	_check_address_info(arguments_res, arguments, location) or_return
	_check_gpu_address(arguments_info, location) or_return

	indirect_parameters_info, indirect_parameters_res := _address_info_of(indirect_parameters)
	_check_address_info(indirect_parameters_res, indirect_parameters, location) or_return
	_check_gpu_address(indirect_parameters_info, location) or_return
 	
	indices_info, indices_res := _address_info_of(indices)
	_check_address_info(indices_res, indices, location) or_return
	_check_gpu_address(indices_info, location) or_return
 	
	return nil
}

_vl_encode_draw_indexed_indirect :: proc(
	cb_metadata:		^_Command_Buffer_Metadata,
	icp_metadata:		^_Indirect_Command_Pool_Metadata,
	pipeline:		Pipeline,
	arguments:		rawptr,
	indices:		rawptr,
	indirect_parameters:	rawptr,
	count:			int,
	location:		runtime.Source_Code_Location,
) -> Result {
	when !ENABLE_VALIDATION do return nil

	_vl_encode_indirect_base(cb_metadata, location) or_return
	_vl_encode_draw_indexed_indirect_base(
		icp_metadata,
		pipeline,
		arguments,
		indirect_parameters,
		indices,
		location,
	) or_return

	_check_condition(
		count >= 0,
		.Invalid_Arguments,
		.Error,
		"Invalid indirect count",
		"The `count` parameter cannot be negative. Count `%d` found.",
		count,
		location=location,
	)
	_check_condition(
		count <= icp_metadata.call_count,
		.Invalid_Arguments,
		.Error,
		"Invalid indirect count",
		"The `count` parameter (%d) cannot greater than the indirect command pool call count (%d).",
		count,
		icp_metadata.call_count,
		location=location,
	)
	

	return nil
}

_vl_encode_draw_indexed_indirect_count :: proc(
	cb_metadata:		^_Command_Buffer_Metadata,
	icp_metadata:		^_Indirect_Command_Pool_Metadata,
	pipeline:		Pipeline,
	arguments:		rawptr,
	indices:		rawptr,
	indirect_parameters:	rawptr,
	count:			rawptr,
	location:		runtime.Source_Code_Location,
) -> Result {
	when !ENABLE_VALIDATION do return nil

	_vl_encode_indirect_base(cb_metadata, location) or_return
	_vl_encode_draw_indexed_indirect_base(
		icp_metadata,
		pipeline,
		arguments,
		indirect_parameters,
		indices,
		location,
	) or_return

	count_info, count_res := _address_info_of(count)
	_check_address_info(count_res, count, location) or_return
	_check_gpu_address(count_info, location) or_return

	return nil
}

_vl_execute_indirect :: proc(
	cb_metadata:	^_Command_Buffer_Metadata,
	ic_metadata:	^_Indirect_Command_Metadata,
	location:	runtime.Source_Code_Location,
) -> Result {
	when !ENABLE_VALIDATION do return nil

	switch ic_metadata.type {
	case .Dispatch:
		_check_condition(
			!cb_metadata.is_encoding_render_pass,
			.Incompatible_Command_Buffer_Stage,
			.Error,
			"Dispatch during render pass.",
			"The indirect command buffer `%v` contains dispatch commands, however a renderpass is " +
			"currently active. It is not possible to submit compute dispatches during renderpasses.",
			ic_metadata.handle,
			location=location,
		) or_return
 
	case .Draw, .Draw_Count, .Draw_Indexed, .Draw_Indexed_Count:
		_check_condition(
			cb_metadata.is_encoding_render_pass,
			.Incompatible_Command_Buffer_Stage,
			.Error,
			"Draw outside of render pass.",
			"The indirect command buffer `%v` contains draw commands, however no renderpass is currently " +
			"active.",
			ic_metadata.handle,
			location=location,
		) or_return
 	}

	return nil
}

_check_indirect_command_pool_handle :: proc(result: Result, indirect_command_pool: Indirect_Command_Pool, location: runtime.Source_Code_Location) -> Result {
	_check_result(
		result,
		.Warning,
		"Invalid resource handle",
		"Invalid indirect command pool handle (%v).",
		indirect_command_pool,
		location=location,
	) or_return
	return nil
}

_indirect_command_pool_metadata_of :: proc(indirect_command_pool: Indirect_Command_Pool) -> (^_Indirect_Command_Pool_Metadata, Result) {
	sync.shared_guard(&_indirect_command_pools_mutex)

	metadata, ok := hm.get(&_indirect_command_pools, indirect_command_pool)
	if !ok {
		return nil, .Invalid_Indirect_Command_Pool
	}
	
	return metadata, nil
}

_add_indirect_command_pool_metadata :: proc() -> (indirect_command_pool: Indirect_Command_Pool, metadata: ^_Indirect_Command_Pool_Metadata, res: Result) {
	sync.guard(&_indirect_command_pools_mutex)

	indirect_command_pool = hm.add(&_indirect_command_pools, _Indirect_Command_Pool_Metadata {}) or_return
	metadata = hm.get(&_indirect_command_pools, indirect_command_pool)

	return
}

_remove_indirect_command_pool_metadata :: proc(indirect_command_pool: Indirect_Command_Pool) {
	sync.guard(&_indirect_command_pools_mutex)

	hm.remove(&_indirect_command_pools, indirect_command_pool)
}

_check_indirect_command_handle :: proc(result: Result, indirect_command: Indirect_Command, location: runtime.Source_Code_Location) -> Result {
	_check_result(
		result,
		.Warning,
		"Invalid resource handle",
		"Invalid indirect command handle (%v).",
		indirect_command,
		location=location,
	) or_return
	return nil
}

_indirect_command_metadata_of :: proc(indirect_command: Indirect_Command) -> (^_Indirect_Command_Metadata, Result) {
	sync.shared_guard(&_indirect_commands_mutex)

	metadata, ok := hm.get(&_indirect_commands, indirect_command)
	if !ok {
		return nil, .Invalid_Indirect_Command
	}
	
	return metadata, nil
}

_add_indirect_command_metadata :: proc() -> (indirect_command: Indirect_Command, metadata: ^_Indirect_Command_Metadata, res: Result) {
	sync.guard(&_indirect_commands_mutex)

	indirect_command = hm.add(&_indirect_commands, _Indirect_Command_Metadata {}) or_return
	metadata = hm.get(&_indirect_commands, indirect_command)

	return
}

_remove_indirect_command_metadata :: proc(indirect_command: Indirect_Command) {
	sync.guard(&_indirect_commands_mutex)

	hm.remove(&_indirect_commands, indirect_command)
}

_handle_indirect_command_lifetime_at_encoding :: proc(
	cb_metadata:	^_Command_Buffer_Metadata,
	ic_metadata:	^_Indirect_Command_Metadata,
) {
	if ic_metadata.lifetime == .One_Shot {
		append(&cb_metadata.indirect_commands_to_free, ic_metadata.handle)
	}
}

_handle_indirect_command_lifetime_at_execution :: proc(
	cb_metadata:	^_Command_Buffer_Metadata,
	ic_metadata:	^_Indirect_Command_Metadata,
) {
	#partial switch ic_metadata.lifetime {
	case .Command_Buffer:
		append(&cb_metadata.indirect_commands_to_free, ic_metadata.handle)

	case .One_Shot:
		ic_metadata.used = true
	}
}

