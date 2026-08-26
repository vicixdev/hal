// NOTE: Gotta keep the LSPs happy :D
#if !defined(GFX_METAL) && !defined(GFX_VULKAN) && !defined(GFX_METAL_ON_VK)
	#define GFX_VULKAN
#endif

#ifdef GFX_METAL

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

#ifdef GFX_METAL_ON_VK

struct Handle_Wrap<T: IOpaqueDescriptor> {
	T>handle;
}

[vk_binding(0, 0)]
StructuredBuffer<Handle_Wrap<SamplerState>>	sampler_set;
[vk_binding(0, 1)]
StructuredBuffer<Handle_Wrap<Texture1D>>		texture_1d_set;
[vk_binding(0, 2)]
StructuredBuffer<Handle_Wrap<Texture2D>>		texture_2d_set;
[vk_binding(0, 3)]
StructuredBuffer<Handle_Wrap<Texture2DArray>>	texture_2d_array_set;
[vk_binding(0, 4)]
StructuredBuffer<Handle_Wrap<TextureCube>>		texture_cube_set;
[vk_binding(0, 5)]
StructuredBuffer<Handle_Wrap<TextureCubeArray>>	texture_cube_array_set;
[vk_binding(0, 6)]
StructuredBuffer<Handle_Wrap<Texture3D>>		texture_3d_set;
[vk_binding(0, 7)]
StructuredBuffer<Handle_Wrap<RWTexture1D>>		storage_texture_1d_set;
[vk_binding(0, 8)]
StructuredBuffer<Handle_Wrap<RWTexture2D>>		storage_texture_2d_set;
[vk_binding(0, 9)]
StructuredBuffer<Handle_Wrap<RWTexture2DArray>>	storage_texture_2d_array_set;
[vk_binding(0, 10)]
StructuredBuffer<Handle_Wrap<RWTexture3D>>		storage_texture_3d_set;

DescriptorHandle<SamplerState> sampler_at(int index) {
	return sampler_set[index].handle;
}

DescriptorHandle<Texture1D> texture_1d_at(int index) {
	return texture_1d_set[index].handle;
}

DescriptorHandle<Texture2D> texture_2d_at(int index) {
	return texture_2d_set[index].handle;
}

DescriptorHandle<Texture2DArray> texture_2d_array_at(int index) {
	return texture_2d_array_set[index].handle;
}

DescriptorHandle<TextureCube> texture_cube_at(int index) {
	return texture_cube_set[index].handle;
}

DescriptorHandle<TextureCubeArray> texture_cube_array_at(int index) {
	return texture_cube_array_set[index].handle;
}

DescriptorHandle<Texture3D> texture_3d_at(int index) {
	return texture_3d_set[index].handle;
}

DescriptorHandle<RWTexture1D> storage_texture_1d_at(int index) {
	return storage_texture_1d_set[index].handle;
}

DescriptorHandle<RWTexture2D> storage_texture_2d_at(int index) {
	return storage_texture_2d_set[index].handle;
}

DescriptorHandle<RWTexture2DArray> storage_texture_2d_array_at(int index) {
	return storage_texture_2d_array_set[index].handle;
}

DescriptorHandle<RWTexture3D> storage_texture_3d_at(int index) {
	return storage_texture_3d_set[index].handle;
}

#endif

