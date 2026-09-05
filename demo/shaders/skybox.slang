import gfx;

struct Vertex {
	float	position[3];

	float3	get_position() {
		return float3(position[0], position[1], position[2]);
	}
}

struct Parameters {
	float4x4	view;
	float4x4	proj;

	Vertex*		vertices;
	uint32_t	skybox_view_index;
	uint32_t	sampler_index;
}

struct Vertex_Output {
	float4	position	: SV_Position;
	float3	sample_coords;
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

	float4 clip = float4(position, 1.0);
	clip = mul(parameters.view, clip);
	clip = mul(parameters.proj, clip);
	clip = mul(NORMALIZE_CLIP_COORDS, clip);

	return Vertex_Output(
		clip.xyww,
		position,
	);
}

[shader("fragment")]
Fragment_Output fragment_main(
	Vertex_Output	input,
) {
	TextureCube	texture = texture_cube_at(parameters.sampler_index);
	SamplerState	sampler = sampler_at(parameters.sampler_index);

	float4 color = texture.Sample(sampler, input.sample_coords);
	return Fragment_Output(color);
}

