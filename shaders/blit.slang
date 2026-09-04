import gfx;

struct Vertex {
	float2	position;
	float2	uv;
}

static const Vertex VERTICES[3] = {
	{
		{ -1.0, -1.0 },
		{  0.0,  1.0 },
	},
	{
		{  3.0, -1.0 },
		{  2.0,  1.0 },
	},
	{
		{ -1.0,  3.0 },
		{  0.0, -1.0 },
	},
};

struct Arguments {
	uint32_t	texture;
	uint32_t	sampler;
	bool		flip_y;
}

struct Vertex_Output {
	float4	position	: SV_Position;
	float2	uv;
}

struct Fragment_Output {
	float4	color;
}

[vk_push_constant]
Arguments*	arguments;

[shader("vertex")]
Vertex_Output vertex_main(
	uint32_t	index	: SV_VertexID,
) {
	Vertex vertex = VERTICES[index];

	float4 clip = float4(vertex.position, 0.0, 1.0);
	clip = normalize_clip(clip);

	float2 uv = normalize_uv(vertex.uv);
	if (arguments.flip_y) {
		uv.y	-=  1.0;
		uv.y	*= -1.0;
	}

	return Vertex_Output(
		clip,
		uv,
	);
}

[shader("fragment")]
Fragment_Output fragment_main(
	Vertex_Output input,
) {
	Texture2D	texture	= texture_2d_at(arguments.texture);
	SamplerState	sampler	= sampler_at(arguments.sampler);

	float4 color = texture.Sample(sampler, input.uv);

	return Fragment_Output(
		color,
	);
}

