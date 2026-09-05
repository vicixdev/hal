// NOTE: Gotta keep the LSPs happy :D
#if !defined(GFX_METAL) && !defined(GFX_VULKAN)
	#define GFX_VULKAN
#endif

#ifdef GFX_METAL

static const float4x4 NORMALIZE_CLIP_COORDS = {
	1, 0, 0, 0,
	0, 1, 0, 0,
	0, 0, 1, 0,
	0, 0, 0, 1,
};

float4 normalize_clip(float4 clip) {
	return clip;
}

float2 normalize_uv(float2 uv) {
	return uv;
}


float3 normalize_cube_uv_coords(float3 d) {
	return d;
}

struct Handle_Wrap<T: IOpaqueDescriptor> {
	DescriptorHandle<T>	handle;
}

struct Resource_Set {
	Handle_Wrap<SamplerState>*	sampler_set;
	Handle_Wrap<Texture1D>*		texture_1d_set;
	Handle_Wrap<Texture2D>*		texture_2d_set;
	Handle_Wrap<Texture2DArray>*	texture_2d_array_set;
	Handle_Wrap<TextureCube>*	texture_cube_set;
	Handle_Wrap<TextureCubeArray>*	texture_cube_array_set;
	Handle_Wrap<Texture3D>*		texture_3d_set;
	Handle_Wrap<RWTexture1D>*	storage_texture_1d_set;
	Handle_Wrap<RWTexture2D>*	storage_texture_2d_set;
	Handle_Wrap<RWTexture2DArray>*	storage_texture_2d_array_set;
	Handle_Wrap<RWTexture3D>*	storage_texture_3d_set;
	uint64_t			_pad;
}

[vk_binding(1, 0)]
ConstantBuffer<Resource_Set>	resource_set: register(b1);

SamplerState sampler_at(int index) {
	return resource_set.sampler_set[index].handle;
}

Texture1D texture_1d_at(int index) {
	return resource_set.texture_1d_set[index].handle;
}

Texture2D texture_2d_at(int index) {
	return resource_set.texture_2d_set[index].handle;
}

Texture2DArray texture_2d_array_at(int index) {
	return resource_set.texture_2d_array_set[index].handle;
}

TextureCube texture_cube_at(int index) {
	return resource_set.texture_cube_set[index].handle;
}

TextureCubeArray texture_cube_array_at(int index) {
	return resource_set.texture_cube_array_set[index].handle;
}

Texture3D texture_3d_at(int index) {
	return resource_set.texture_3d_set[index].handle;
}

RWTexture1D storage_texture_1d_at(int index) {
	return resource_set.storage_texture_1d_set[index].handle;
}

RWTexture2D storage_texture_2d_at(int index) {
	return resource_set.storage_texture_2d_set[index].handle;
}

RWTexture2DArray storage_texture_2d_array_at(int index) {
	return resource_set.storage_texture_2d_array_set[index].handle;
}

RWTexture3D storage_texture_3d_at(int index) {
	return resource_set.storage_texture_3d_set[index].handle;
}

#endif

#ifdef GFX_VULKAN

static const float4x4 NORMALIZE_CLIP_COORDS = {
	1,  0,   0, 0,
	0, -1,   0, 0,
	0,  0, 0.5, 0,
	0,  0, 0.5, 1,
};

float4 normalize_clip(float4 clip) {
	return mul(NORMALIZE_CLIP_COORDS, clip);
}

float2 normalize_uv(float2 uv) {
	// return float2(uv.x, 1.0 - uv.y);
	return uv;
}

[vk_binding(0)]
SamplerState		sampler_set[];
[vk_binding(1)]
Texture1D		texture_1d_set[];
[vk_binding(2)]
Texture2D		texture_2d_set[];
[vk_binding(3)]
Texture2DArray		texture_2d_array_set[];
[vk_binding(4)]
TextureCube		texture_cube_set[];
[vk_binding(5)]
TextureCubeArray	texture_cube_array_set[];
[vk_binding(6)]
Texture3D		texture_3d_set[];
[vk_binding(7)]
RWTexture1D		storage_texture_1d_set[];
[vk_binding(8)]
RWTexture2D		storage_texture_2d_set[];
[vk_binding(9)]
RWTexture2DArray	storage_texture_2d_array_set[];
[vk_binding(10)]
RWTexture3D		storage_texture_3d_set[];

SamplerState sampler_at(int index) {
	return sampler_set[index];
}

Texture1D texture_1d_at(int index) {
	return texture_1d_set[index];
}

Texture2D texture_2d_at(int index) {
	return texture_2d_set[index];
}

Texture2DArray texture_2d_array_at(int index) {
	return texture_2d_array_set[index];
}

TextureCube texture_cube_at(int index) {
	return texture_cube_set[index];
}

TextureCubeArray texture_cube_array_at(int index) {
	return texture_cube_array_set[index];
}

Texture3D texture_3d_at(int index) {
	return texture_3d_set[index];
}

RWTexture1D storage_texture_1d_at(int index) {
	return storage_texture_1d_set[index];
}

RWTexture2D storage_texture_2d_at(int index) {
	return storage_texture_2d_set[index];
}

RWTexture2DArray storage_texture_2d_array_at(int index) {
	return storage_texture_2d_array_set[index];
}

RWTexture3D storage_texture_3d_at(int index) {
	return storage_texture_3d_set[index];
}

#endif

