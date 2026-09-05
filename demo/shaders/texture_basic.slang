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
	float4x4	model;
	float4x4	view;
	float4x4	proj;

	Vertex*		vertices;
	uint32_t	texture;
	uint32_t	sampler;
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
	uint32_t index : SV_VertexID,
) {

	float2 uv = parameters.vertices[index].get_uv();
	uv = normalize_uv(uv);

	float3 position = parameters.vertices[index].get_position();
	// clip = NORMALIZE_CLIP_COORDS * proj * view * model * position
	float4 clip = float4(position, 1.0);
	clip = mul(parameters.model, clip);
	clip = mul(parameters.view, clip);
	clip = mul(parameters.proj, clip);
	clip = normalize_clip(clip);

	return Vertex_Output(
		clip,
		uv,
	);
}

[shader("fragment")]
Fragment_Output fragment_main(
	Vertex_Output	input,
) {
	Texture2D	texture = texture_2d_at(parameters.texture);
	SamplerState	sampler = sampler_at(parameters.sampler);

	float4 color = texture.Sample(sampler, input.uv);

	return Fragment_Output(color);
}
