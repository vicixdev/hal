import gfx;

struct Vertex {
	float	position[2];
	float	uv	[2];

	float2	get_position() {
		return float2(position[0], position[1]);
	}

	float2	get_uv() {
		return float2(uv[0], uv[1]);
	}
}

struct Quad {
	Vertex		vertices[4];
	float		color	[4];
	uint32_t	texture;
	float		color_factor;

	float4	get_color() {
		return float4(color[0], color[1], color[2], color[3]);
	}
}

struct Arguments {
	Quad*		quads;
	float		screen_dimensions[2];
}

struct Vertex_Output {
	float4		position	: SV_Position;
	float4		color;
	float2		uv;
	float		color_factor;
	uint32_t	texture;
}

struct Fragment_Output {
	float4	color;
}

[vk_push_constant]
uniform Arguments* arguments;

[shader("vertex")]
Vertex_Output vertex_main(
	uint32_t	index		: SV_VertexID,
	uint32_t	instance	: SV_InstanceID,
) {

	static_assert(sizeof(Vertex)	== 16, "Unexpected size");
	static_assert(sizeof(Quad)	== 88, "Unexpected size");
	static_assert(sizeof(Arguments)	== 16, "Unexpected size");

	Quad*	quad	= __getAddress(arguments.quads[instance]);
	Vertex*	vertex	= __getAddress(quad.vertices[index]);

	float4 position = float4(vertex.get_position(), 0.0, 1.0);
	position *= float4(2.0, 2.0, 1.0, 1.0);
	position /= float4(arguments.screen_dimensions[0], arguments.screen_dimensions[1], 1.0, 1.0);
	position -= float4(1.0, 1.0, 0.0, 0.0);
	position = normalize_clip(position);

	float2 uv	= normalize_uv(vertex.get_uv());
	float4 color	= quad.get_color();

	return Vertex_Output(
		position,
		color,
		uv,
		quad.color_factor,
		quad.texture,
	);
}

[shader("fragment")]
Fragment_Output fragment_main(
	Vertex_Output	input,
) {
	Texture2D	texture = texture_2d_at(input.texture);
	SamplerState	sampler = sampler_at(0);

	float4 sample_color = texture.Sample(sampler, input.uv);
	sample_color = float4(input.color.rgb, sample_color.r);

	float4 color = input.color * input.color_factor + sample_color * (1.0 - input.color_factor);

	return Fragment_Output(color);
}

