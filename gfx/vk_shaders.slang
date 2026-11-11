struct Dispatch_Indirect_Parameters {
	int64_t group_count[3];
}

struct vk_Dispatch_Indirect_Command {
	uint32_t x;
	uint32_t y;
	uint32_t z;
}

struct Encode_Dispatch_Arguments {
	Dispatch_Indirect_Parameters* source;
	vk_Dispatch_Indirect_Command* destination;
}

[vk_push_constant]
uniform Encode_Dispatch_Arguments dispatch_arguments;

[shader("compute")]
[numthreads(1, 1, 1)]
void encode_dispatch() {
	dispatch_arguments.destination.x = uint32_t(dispatch_arguments.source.group_count[0]);
	dispatch_arguments.destination.y = uint32_t(dispatch_arguments.source.group_count[1]);
	dispatch_arguments.destination.z = uint32_t(dispatch_arguments.source.group_count[2]);
}


void write_draw_dispatch(
	vk_Dispatch_Indirect_Command* dispatch,
	uint32_t count
) {
	dispatch.x = count;
	dispatch.y = 1;
	dispatch.z = 1;
}


struct Prepare_Draw_Encoding_Dispatch_Arguments {
	vk_Dispatch_Indirect_Command* dispatch;
	uint32_t count;
}

[vk_push_constant]
uniform Prepare_Draw_Encoding_Dispatch_Arguments prepare_draw_encoding_dispatch_arguments;

[shader("compute")]
[numthreads(1, 1, 1)]
void prepare_draw_encoding_dispatch() {
	write_draw_dispatch(
		prepare_draw_encoding_dispatch_arguments.dispatch,
		prepare_draw_encoding_dispatch_arguments.count
	);
}


struct Prepare_Draw_Encoding_Dispatch_Count_Arguments {
	vk_Dispatch_Indirect_Command* dispatch;
	uint32_t* count;
}

[vk_push_constant]
uniform Prepare_Draw_Encoding_Dispatch_Count_Arguments prepare_draw_encoding_dispatch_count_arguments;

[shader("compute")]
[numthreads(1, 1, 1)]
void prepare_draw_encoding_dispatch_count() {
	write_draw_dispatch(
		prepare_draw_encoding_dispatch_count_arguments.dispatch,
		*prepare_draw_encoding_dispatch_count_arguments.count
	);
}


struct Draw_Indirect_Parameters {
	int64_t vertex_count;
	int64_t instance_count;
	int64_t base_vertex;
}

struct vk_Draw_Indirect_Command {
	uint32_t vertex_count;
	uint32_t instance_count;
	uint32_t first_vertex;
	uint32_t first_instance;
	uint32_t _padding;
}

struct Encode_Draw_Arguments {
	Draw_Indirect_Parameters* source;
	vk_Draw_Indirect_Command* destination;
}

[vk_push_constant]
uniform Encode_Draw_Arguments draw_arguments;

[shader("compute")]
[numthreads(1, 1, 1)]
void encode_draw(uint3 thread_id : SV_DispatchThreadID) {
	uint index = thread_id.x;

	Draw_Indirect_Parameters source = draw_arguments.source[index];
	draw_arguments.destination[index] = vk_Draw_Indirect_Command(
		uint32_t(source.vertex_count),
		uint32_t(source.instance_count),
		uint32_t(source.base_vertex),
		0,
		0
	);
}


struct Draw_Indexed_Indirect_Parameters {
	int64_t index_count;
	int64_t instance_count;
	int64_t base_index;
}

struct vk_Draw_Indexed_Indirect_Command {
	uint32_t index_count;
	uint32_t instance_count;
	uint32_t first_index;
	int32_t vertex_offset;
	uint32_t first_instance;
}

struct Encode_Indexed_Draw_Arguments {
	Draw_Indexed_Indirect_Parameters* source;
	vk_Draw_Indexed_Indirect_Command* destination;
}

[vk_push_constant]
uniform Encode_Indexed_Draw_Arguments indexed_draw_arguments;

[shader("compute")]
[numthreads(1, 1, 1)]
void encode_indexed_draw(uint3 thread_id: SV_DispatchThreadID) {
	uint index = thread_id.x;

	Draw_Indexed_Indirect_Parameters source = indexed_draw_arguments.source[index];
	indexed_draw_arguments.destination[index] = vk_Draw_Indexed_Indirect_Command(
		uint32_t(source.index_count),
		uint32_t(source.instance_count),
		uint32_t(source.base_index),
		0,
		0
	);
}
