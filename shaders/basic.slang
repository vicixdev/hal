struct Params {
	float*	in_a;
	float*	in_b;
	float*	out;
}

struct Handle_Wrap<T: IOpaqueDescriptor> {
	DescriptorHandle<T>	handle;
}

struct SamplerWrap {
	DescriptorHandle<SamplerState>	sampler_state;
}
struct Texture1DWrap {
	DescriptorHandle<Texture1D>	texture;
}
struct RWTexture1DWrap {
	DescriptorHandle<RWTexture1D>	texture;
}

enum Texture_Type{
	D1,
	D2,
	D2_Array,
	Cube,
	Cube_Array,
	D3,
}

enum Storage_Texture_Type {
	D1,
	D2,
	D2_Array,
	D3,
}

struct Resource_Set {
	Handle_Wrap<SamplerState>*	sampler_set;
	Handle_Wrap<Texture1D>*		d1_texture_set;
	Handle_Wrap<Texture2D>*		d2_texture_set;
	Handle_Wrap<Texture2DArray>*	d2_array_texture_set;
	Handle_Wrap<TextureCube>*	cube_texture_set;
	Handle_Wrap<TextureCubeArray>*	cube_array_texture_set;
	Handle_Wrap<Texture3D>		d3_texture_set;
	Handle_Wrap<RWTexture1D>*	d1_storage_texture_set;
	Handle_Wrap<RWTexture2D>*	d2_storage_texture_set;
	Handle_Wrap<RWTexture2DArray>*	d2_array_storage_texture_set;
	Handle_Wrap<RWTexture3D>*	d3_storage_texture_set;
}

ConstantBuffer<Params>		params;
ConstantBuffer<Resource_Set>	resource_set;

[shader("compute")]
[numthreads(16,16,1)]
void computeMain(
	uint3 threadId : SV_DispatchThreadID,
) {
	uint index = threadId.x;

	// // params.out[index] = params.in_a[index] + params.in_b[index];
	// params.out[index] = params.in_a[index] + params.in_b[index] *
	// 	nonuniform(d2_texture_set[index]).Sample(sampler_set[0], { 0, 0 }).x;
	// float4 value = nonuniform(d1_texture_set[index].texture).Sample(sampler_set[0].sampler_state, 0.5);
	// nonuniform(d1_storage_texture_set[index].texture).Store(index, value);

	Texture1D tex = nonuniform(resource_set.d1_texture_set[index + 1].handle);
	SamplerState sampl = resource_set.sampler_set[0].handle;
	RWTexture1D res = resource_set.d1_storage_texture_set[0].handle;

	float4 pix = tex.Sample(sampl, index);
	res.Store(index, pix);
}

