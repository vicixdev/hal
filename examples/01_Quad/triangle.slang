import gfx;

struct Vertex {
	float	position[3];
	float	color[3];

	float3	get_position() {
		return float3(position[0], position[1], position[2]);
	}

	float3	get_color() {
		return float3(color[0], color[1], color[2]);
	}
}

struct Parameters {
	Vertex*	vertices;
}

struct Vertex_Output {
	float4	position	: SV_Position;
	float3	color;
}

struct Fragment_Output {
	float4	color;
}

[vk_push_constant]
uniform Parameters* parameters;

[shader("vertex")]
Vertex_Output vertex_main(
	uint32_t index	: SV_VertexID,
) {
	static_assert(sizeof(Vertex) == 24, "Unxpected Vertex size.");

	float3 position = parameters.vertices[index].get_position();
	float3 color = parameters.vertices[index].get_color();

	return Vertex_Output(
		mul(NORMALIZE_CLIP_COORDS, float4(position, 1.0)),
		color,
	);
}

[shader("fragment")]
Fragment_Output fragment_main(Vertex_Output input) {
	return Fragment_Output(float4(input.color, 1.0));
}

