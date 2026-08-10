import gfx;

struct Params {
	float*	in_a;
	float*	in_b;
	float*	out;
}

[shader("compute")]
[numthreads(16,16,1)]
void computeMain(
	uint3 threadId : SV_DispatchThreadID,
	uniform Params params,
) {
	uint index = threadId.x;

	// // params.out[index] = params.in_a[index] + params.in_b[index];
	// params.out[index] = params.in_a[index] + params.in_b[index] *
	// 	nonuniform(d2_texture_set[index]).Sample(sampler_set[0], { 0, 0 }).x;
	// float4 value = nonuniform(d1_texture_set[index].texture).Sample(sampler_set[0].sampler_state, 0.5);
	// nonuniform(d1_storage_texture_set[index].texture).Store(index, value);

	Texture1D tex = nonuniform(texture_1d_at(index + 1));
	SamplerState sampl = sampler_at(0);
	RWTexture1D res = storage_texture_1d_at(0);

	float4 pix = tex.Sample(sampl, index);
	res.Store(index, pix);
}

