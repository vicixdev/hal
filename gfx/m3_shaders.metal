/*
Copyright (c) 2026 Vicix (https://github.com/vicixdev)

This Source Code Form is subject to the terms of the Mozilla Public
License, v. 2.0. If a copy of the MPL was not distributed with this
file, You can obtain one at https://mozilla.org/MPL/2.0/.
*/

#include <metal_stdlib>
#include <metal_atomic>

using namespace metal;

struct gfx_Dispatch_Indirect_Parameters {
	int64_t	group_count[3];
};

struct Encode_Dispatch_Indirect_Arguments {
	device	gfx_Dispatch_Indirect_Parameters*		source;
	device	MTLDispatchThreadgroupsIndirectArguments*	destination;
};
void kernel encode_dispatch_indirect(
			uint					thread_id	[[thread_position_in_grid]],
	constant	Encode_Dispatch_Indirect_Arguments&	arguments	[[buffer(0)]]
) {
	if (thread_id > 0) {
		return;
	}

	device gfx_Dispatch_Indirect_Parameters* source = arguments.source;
	device MTLDispatchThreadgroupsIndirectArguments* destination = arguments.destination;

	destination->threadgroupsPerGrid[0] = (uint)source->group_count[0];
	destination->threadgroupsPerGrid[1] = (uint)source->group_count[1];
	destination->threadgroupsPerGrid[2] = (uint)source->group_count[2];
}


struct Draw_ICP_Call_Data {
	device uint8_t* arguments;
	uint16_t draw_id;
	uint16_t _padding[3];
};
static_assert(sizeof(Draw_ICP_Call_Data) == 16);

struct Draw_ICP {
	uint32_t	command_count;
	uint32_t	call_count;
	// GPU atomic counter. Points to the first available location in the `buffer.icbs` and the
	//	`buffer.encode_params`buffer.
	atomic_uint	index;
	uint32_t	_pad_0;

	command_buffer	icbs;

	// Contains
	//	ranges:		[command_count]MTLIndirectCommandBufferExecutionRange,
	//	encode_params:	[command_count]MTLDispatchThreadgroupsIndirectArguments,
	//	draw_data:	[call_count]Draw_ICP_Call_Data,
	uint8_t		dynamic_data[1];

	device MTLIndirectCommandBufferExecutionRange*	indirect_execution_range_at(int i) {
		int offset = i * sizeof(MTLIndirectCommandBufferExecutionRange);
		return (device MTLIndirectCommandBufferExecutionRange*)&dynamic_data[offset];
	}

	device MTLDispatchThreadgroupsIndirectArguments* encode_params_at(int i) {
		int offset = sizeof(MTLIndirectCommandBufferExecutionRange) * command_count +
			sizeof(MTLDispatchThreadgroupsIndirectArguments) * i;
		return (device MTLDispatchThreadgroupsIndirectArguments*)&dynamic_data[offset];
	}

	device Draw_ICP_Call_Data* call_data_at(int i) {
		int offset = sizeof(MTLIndirectCommandBufferExecutionRange) * command_count +
			sizeof(MTLDispatchThreadgroupsIndirectArguments) * command_count +
			sizeof(Draw_ICP_Call_Data) * i;
		return (device Draw_ICP_Call_Data*)&dynamic_data[offset];
	}
};
static_assert(sizeof(Draw_ICP) == 32);

void allocate_execution_range_in(
	device	Draw_ICP*					pool,
	device	MTLIndirectCommandBufferExecutionRange*		destination,
		uint64_t					count
) {
	if (count > pool->call_count) {
		destination->location = 0;
		destination->length = 0;
		return;
	}

	uint start;

	for (;;) {
		uint value = atomic_load_explicit(&pool->index, memory_order_relaxed);

		start = value;
		uint next_value = value + count;
		if (next_value > pool->call_count) {
			start = 0;
			next_value = count;
		}

		bool did_exchange = atomic_compare_exchange_weak_explicit(
			&pool->index,
			&value,
			next_value,
			memory_order_relaxed,
			memory_order_relaxed
		);
		if (did_exchange) {
			break;
		}
	}

	destination->location = start;
	destination->length = count;
}

void encode_encode_icbs_params(
	device	MTLDispatchThreadgroupsIndirectArguments*	encode_icbs_dispatch_params,
		uint64_t					count
) {
	constexpr uint ENCODE_ICBS_THREADGROUP_SIZE = 256;
	uint threadgroup_count = (count + ENCODE_ICBS_THREADGROUP_SIZE-1) / ENCODE_ICBS_THREADGROUP_SIZE;

	encode_icbs_dispatch_params->threadgroupsPerGrid[0] = threadgroup_count;
	encode_icbs_dispatch_params->threadgroupsPerGrid[1] = 1;
	encode_icbs_dispatch_params->threadgroupsPerGrid[2] = 1;
}

struct Allocate_ICB_Range_Arguments {
	device	Draw_ICP*					pool;
	device	MTLIndirectCommandBufferExecutionRange*		destination;
	device	MTLDispatchThreadgroupsIndirectArguments*	encode_icbs_dispatch_params;
		uint64_t					count;
};
void kernel allocate_icb_range(
		uint				thread_id	[[thread_position_in_grid]],
	constant Allocate_ICB_Range_Arguments&	arguments	[[buffer(0)]]
) {
	if (thread_id > 0) {
		return;
	}

	allocate_execution_range_in(arguments.pool, arguments.destination, arguments.count);
	encode_encode_icbs_params(arguments.encode_icbs_dispatch_params, arguments.count);
}

struct Allocate_ICB_Range_Count_Arguments {
	device	Draw_ICP*					pool;
	device	MTLIndirectCommandBufferExecutionRange*		destination;
	device	MTLDispatchThreadgroupsIndirectArguments*	encode_icbs_dispatch_params;
	constant uint64_t*					count;
};
void kernel allocate_icb_range_count(
		uint					thread_id	[[thread_position_in_grid]],
	constant Allocate_ICB_Range_Count_Arguments&	arguments	[[buffer(0)]]
) {
	if (thread_id > 0) {
		return;
	}

	uint64_t count = *arguments.count;

	allocate_execution_range_in(arguments.pool, arguments.destination, count);
	encode_encode_icbs_params(arguments.encode_icbs_dispatch_params, count);
}

struct DrawIndirectParameters {
	int64_t	vertex_count;
	int64_t	instance_count;
	int64_t	base_vertex;
};
struct EncodeDrawICBsArguments {
	device	Draw_ICP*					pool;
	constant MTLIndirectCommandBufferExecutionRange*	execution_range;
	constant DrawIndirectParameters*			draw_parameters;
	device	uint8_t*					arguments;
	device	uint8_t*					resource_set;
		primitive_type					primitive;
};
void kernel encode_draw_icbs(
		uint				thread_id	[[thread_position_in_grid]],
	constant EncodeDrawICBsArguments&	arguments	[[buffer(0)]]
) {
	uint start = arguments.execution_range->location;
	uint max = start + arguments.execution_range->length;
	uint target = start + thread_id;

	if (target >= max) {
		return;
	}

	device Draw_ICP_Call_Data* call_data = arguments.pool->call_data_at(target);
	call_data->arguments = arguments.arguments;
	call_data->draw_id = thread_id;

	DrawIndirectParameters parameters = arguments.draw_parameters[thread_id];

	render_command cmd(arguments.pool->icbs, target);
	cmd.set_vertex_buffer(&call_data->arguments, 0);
	cmd.set_fragment_buffer(&call_data->arguments, 0);
	cmd.set_vertex_buffer(arguments.resource_set, 1);
	cmd.set_fragment_buffer(arguments.resource_set, 1);
	cmd.set_vertex_buffer((device uint8_t*)&call_data->draw_id, 2);
	cmd.set_fragment_buffer((device uint8_t*)&call_data->draw_id, 2);
	cmd.draw_primitives(arguments.primitive, parameters.base_vertex, parameters.vertex_count, parameters.instance_count, 0);

}

struct DrawIndexedIndirectParameters {
	int64_t	index_count;
	int64_t	instance_count;
	int64_t	base_index;
};
struct EncodeICBsDrawIndexedArguments {
	device	Draw_ICP*					pool;
	constant MTLIndirectCommandBufferExecutionRange*	execution_range;
	constant DrawIndexedIndirectParameters*			draw_parameters;
	device	uint8_t*					arguments;
	device	uint8_t*					resource_set;
		uintptr_t					indices;
		primitive_type					primitive;
		bool						index_type;
};
void kernel encode_draw_indexed_icbs(
		uint					thread_id	[[thread_position_in_grid]],
	constant EncodeICBsDrawIndexedArguments&	arguments	[[buffer(0)]]
) {
	uint start = arguments.execution_range->location;
	uint max = start + arguments.execution_range->length;
	uint target = start + thread_id;

	if (target >= max) {
		return;
	}

	device Draw_ICP_Call_Data* call_data = arguments.pool->call_data_at(target);
	call_data->arguments = arguments.arguments;
	call_data->draw_id = thread_id;

	DrawIndexedIndirectParameters parameters = arguments.draw_parameters[thread_id];

	uint index_size = (arguments.index_type + 1) * 2;
	uintptr_t first_index = arguments.indices + index_size * parameters.base_index;

	render_command cmd(arguments.pool->icbs, target);
	cmd.set_vertex_buffer(&call_data->arguments, 0);
	cmd.set_fragment_buffer(&call_data->arguments, 0);
	cmd.set_vertex_buffer(arguments.resource_set, 1);
	cmd.set_fragment_buffer(arguments.resource_set, 1);
	cmd.set_vertex_buffer((device uint8_t*)&call_data->draw_id, 2);
	cmd.set_fragment_buffer((device uint8_t*)&call_data->draw_id, 2);
	if (arguments.index_type == 0) {
		device ushort* indices = (device ushort*)first_index;
		cmd.draw_indexed_primitives(
			arguments.primitive,
			parameters.index_count,
			indices,
			parameters.instance_count,
			0,
			0
		);
	} else {
		device uint* indices = (device uint*)first_index;
		cmd.draw_indexed_primitives(
			arguments.primitive,
			parameters.index_count,
			indices,
			parameters.instance_count,
			0,
			0
		);
	}
}
