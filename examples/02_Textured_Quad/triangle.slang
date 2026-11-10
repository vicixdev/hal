import gfx;

struct Vertex {
	float	position[3];
	float	uv[2];

	float3	get_position() {
		return float3(position[0], position[1], position[2]);
	}

	float2	get_uv() {
		return float2(uv[0], uv[1]);
	}
}

struct Parameters {
	Vertex*		vertices;
	uint32_t	texture_index;
}

struct Vertex_Output {
	float4	position	: SV_Position;
	float2	uv;
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
	static_assert(sizeof(Vertex) == 20, "Unxpected Vertex size.");

	float3 position = parameters.vertices[index].get_position();
	float2 uv = parameters.vertices[index].get_uv();

	return Vertex_Output(
		normalize_clip(float4(position, 1.0)),
		normalize_uv(uv),
	);
}

[shader("fragment")]
Fragment_Output fragment_main(Vertex_Output input) {
	Texture2D texture = texture_2d_at(parameters.texture_index);
	SamplerState sampler = sampler_at(0);

	return Fragment_Output(texture.Sample(sampler, input.uv));
}

