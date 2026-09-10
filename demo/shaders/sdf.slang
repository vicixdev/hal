import gfx;

// [vk_constant_id(0)]
const static float ATLAS_SIZE = 4098.0f;
const static uint16_t INDICES[] = {
	0, 1, 2,
	2, 3, 0,
};

struct Vertex {
	float		position[2];
	uint16_t	uv	[2];

	float2		get_position() {
		static_assert(sizeof(Vertex) == 12, "");

		return float2(position[0], position[1]);
	}

	float2		get_uv() {
		return float2((float)uv[0], (float)uv[1]) / ATLAS_SIZE;
	}
}

struct Glyph {
	Vertex		vertices[4];
	uint8_t		color	[4];
	uint16_t	texture;

	float4		get_color() {
		static_assert(sizeof(Glyph) == 12 * 4 + 4 + 2,"");

		return float4(
			(float)color[0],
			(float)color[1],
			(float)color[2],
			(float)color[3],
		) / 255.0;
	}
}

struct Arguments {
	Glyph**		glyphs;
	uint16_t	screen_size	[2];
	uint16_t	sampler;

	Vertex*		get_vertex(int glyph, int idx) {
		return __getAddress(glyphs[glyph].vertices[idx]);
	}

	Glyph*		get_glyph(int idx) {
		return glyphs[idx];
	}

	float2		get_screen_size() {
		return float2((float)screen_size[0], (float)screen_size[1]);
	}
}

struct Vertex_Output {
	float4		position	: SV_Position;
	float4		color;
	float2		uv;
	uint		texture;
	uint		sampler;
}

struct Fragment_Output {
	float4		color;
}

[vk_push_constant]
uniform Arguments* arguments;

[shader("vertex")]
Vertex_Output vertex_main(
	uint	vertex_id	: SV_VertexID,
	uint	instance_id	: SV_InstanceID,
) {
	
	// uint16_t index	= INDICES[vertex_id];

	Glyph*	glyph	= arguments.get_glyph(instance_id);
	Vertex*	vertex	= arguments.get_vertex(instance_id, vertex_id);
	
	float2	screen_size	= arguments.get_screen_size();
	float4	color		= glyph.get_color();
	float2	position	= vertex.get_position();
	float2	uv		= vertex.get_uv();

	float2 ndc = position / screen_size * 2.0 - 1.0;
	float4 clip = normalize_clip(float4(ndc.x, -ndc.y, 0.0, 1.0));

	return Vertex_Output(
		clip,
		color,
		uv,
		glyph.texture,
		arguments.sampler,
	);
}

[shader("fragment")]
Fragment_Output fragment_main(
	Vertex_Output	input,
) {
	
	Texture2D	texture = texture_2d_at(input.texture);
	SamplerState	sampler	= sampler_at(input.sampler);

	float alpha = texture.Sample(sampler, input.uv).x;
	// float width = fwidth(sdf);
	// float alpha = smoothstep(
	// 	0.5 - width,
	// 	0.5 + width,
	// 	sdf,
	// );

	float4 color = float4(
		input.color.rgb,
		alpha,
	);

	return Fragment_Output(
		color,
	);
}

