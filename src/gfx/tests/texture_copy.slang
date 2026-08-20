#include "../../../shaders/gfx.slang"

struct Parameters {
	uint2	size;
	uint	texture_in;
	uint	texture_out;
}

[push_constant]
Parameters parameters;

[shader("compute")]
[numthreads(16,16,1)]
void texture_copy(
	uint3 thread_id : SV_DispatchThreadID,
) {
	static_assert(sizeof(Parameters) == 16, "Unexpected parameters size.");

	if (thread_id.x >= parameters.size.x || thread_id.y >= parameters.size.y) {
		return;
	}

	RWTexture2D input_texture = storage_texture_2d_at(parameters.texture_in);
	RWTexture2D output_texture = storage_texture_2d_at(parameters.texture_out);

	float4 pixel = input_texture.Load(thread_id.xy);
	output_texture.Store(thread_id.xy, pixel);
}
