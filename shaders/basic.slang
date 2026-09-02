import gfx;

struct Vertex {
	float	position[3];
	float	color[4];

	float3	get_position() {
		return float3(position[0], position[1], position[2]);
	}

	float4	get_color() {
		return float4(color[0], color[1], color[2], color[3]);
	}
}

struct Parameters {
	float4x4	model;
	float4x4	view;
	float4x4	proj;

	Vertex*		vertices;
}

struct Vertex_Output {
	float4	position	: SV_Position;
	float4	color;
}

struct Fragment_Output {
	float4	color;
}

[vk_push_constant]
uniform Parameters* parameters;

[shader("vertex")]
Vertex_Output vertex_main(
	uint32_t index : SV_VertexID,
) {
	float3 position = parameters.vertices[index].get_position();
	float4 color = parameters.vertices[index].get_color();

	// clip = NORMALIZE_CLIP_COORDS * proj * view * model * position
	float4 clip = float4(position, 1.0);
	clip = mul(parameters.model, clip);
	clip = mul(parameters.view, clip);
	clip = mul(parameters.proj, clip);
	clip = mul(NORMALIZE_CLIP_COORDS, clip);

	return Vertex_Output(
		clip,
		color,
	);
}

[shader("fragment")]
Fragment_Output fragment_main(
	Vertex_Output	input,
) {
	return Fragment_Output(input.color);
}

