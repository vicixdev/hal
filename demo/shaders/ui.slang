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

struct Arguments {
	Vertex*		vertices;
	uint8_t		color	[4];
	uint16_t	texture;
	uint16_t	sampler;
	uint8_t		factors	[3];
	uint8_t		vertices_per_strip;
	int16_t		z_index;

	float4	get_color() {
		return float4(color[0], color[1], color[2], color[3]) / 255.0;
	}

	float	get_z() {
		return ((float)z_index / 32766.0 + 1.0) / 2.0;
	}

	float	get_color_factor() {
		return (float)factors[0];
	}

	float	get_text_factor() {
		return (float)factors[1];
	}

	float	get_texture_factor() {
		return (float)factors[2];
	}
}

struct Vertex_Out {
	float4		position	: SV_Position;
	uint		texture;
	uint		sampler;
	float2		uv;
	float4		color;
	float		color_factor;
	float		text_factor;
	float		texture_factor;
}

struct Fragment_Out {
	float4	color;
}

[vk_push_constant]
uniform Arguments* arguments;

[shader("vertex")]
Vertex_Out vertex_main(
	uint	index	: SV_VertexID,
	uint	instance: SV_InstanceID,
) {
	
	static_assert(sizeof(Arguments) == 22, "Unexpected Arguments size.");
	static_assert(sizeof(Vertex) == 16, "Unexpected Vertex size.");

	uint vertex_index = arguments.vertices_per_strip * instance + index;
	Vertex vertex = arguments.vertices[vertex_index];

	float2 vertex_position = vertex.get_position();
	float z = arguments.get_z();

	Vertex_Out output;
	output.position		= normalize_clip(float4(vertex_position, z, 1.0));
	output.texture		= arguments.texture;
	output.sampler		= arguments.sampler;
	output.uv		= vertex.get_uv();
	output.color		= arguments.get_color();
	output.color_factor	= arguments.get_color_factor();
	output.text_factor	= arguments.get_text_factor();
	output.texture_factor	= arguments.get_texture_factor();

	return output;
}

[shader("fragment")]
Fragment_Out fragment_main(Vertex_Out input) {
	
	Texture2D texture = texture_2d_at(input.texture);
	SamplerState sampler = sampler_at(input.sampler);

	float4 tex_color = texture.Sample(sampler, input.uv);

	float4 color_component	= input.color;
	float4 text_component	= float4(input.color.rgb, tex_color.r);
	float4 texture_component = tex_color;

	float4 color = input.color_factor * color_component +
		input.text_factor * text_component +
		input.texture_factor * texture_component;

	return Fragment_Out(color);
}
