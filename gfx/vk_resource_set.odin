package vicixdev_gfx

import vk "vendor:vulkan"

vk_Resource_Set_Metadata :: struct {
	descriptor_set:	vk.DescriptorSet,
}

vk_create_resource_set :: proc(metadata: ^_Resource_Set_Metadata) -> Result {
	descriptor_set_info := vk.DescriptorSetAllocateInfo {
		sType			= .DESCRIPTOR_SET_ALLOCATE_INFO,
		descriptorPool		= vk_descriptor_pool,
		descriptorSetCount	= 1,
		pSetLayouts		= &vk_descriptor_set_layout,
	}
	vk_call(vk.AllocateDescriptorSets(
		vk_device,
		&descriptor_set_info,
		&metadata.vk.descriptor_set,
	)) or_return

	return nil
}

vk_destroy_resource_set :: proc(metadata: ^_Resource_Set_Metadata) -> Result {
	vk.FreeDescriptorSets(vk_device, vk_descriptor_pool, 1, &metadata.vk.descriptor_set)

	return nil
}

vk_set_texture_set :: proc(metadata: ^_Resource_Set_Metadata, type: View_Type) -> Result {
	textures_infos := make([]vk.DescriptorImageInfo, len(metadata.texture_sets[type]), _temp_allocator) or_return
	for view, i in metadata.texture_sets[type] {
		view_metadata := _metadata_of(view) or_return

		textures_infos[i] = {
			imageView	= view_metadata.vk.view,
			imageLayout	= .SHADER_READ_ONLY_OPTIMAL,
		}
	}

	binding: vk_Descriptor_Binding
	switch type {
	case .D1:
		binding = .Texture_1d_Sampled_Image
	case .D2:
		binding = .Texture_2d_Sampled_Image
	case .D2_Array:
		binding = .Texture_2d_Array_Sampled_Image
	case .Cube:
		binding = .Texture_Cube_Sampled_Image
	case .Cube_Array:
		binding = .Texture_Cube_Array_Sampled_Image
	case .D3:
		binding = .Texture_3d_Sampled_Image
	}
	
	update := vk.WriteDescriptorSet {
		sType		= .WRITE_DESCRIPTOR_SET,
		dstSet		= metadata.vk.descriptor_set,
		dstBinding	= cast(u32)binding,
		dstArrayElement	= 0,
		descriptorCount	= cast(u32)len(textures_infos),
		descriptorType	= .SAMPLED_IMAGE,
		pImageInfo	= raw_data(textures_infos),
	}
	vk.UpdateDescriptorSets(vk_device, 1, &update, 0, nil)

	return nil
}

vk_set_storage_texture_set :: proc(metadata: ^_Resource_Set_Metadata, type: Storage_View_Type) -> Result {
	textures_infos := make([]vk.DescriptorImageInfo, len(metadata.storage_texture_sets[type]), _temp_allocator) or_return
	for view, i in metadata.storage_texture_sets[type] {
		view_metadata := _metadata_of(view) or_return

		textures_infos[i] = {
			imageView	= view_metadata.vk.view,
			imageLayout	= .GENERAL,
		}
	}

	binding: vk_Descriptor_Binding
	#partial switch type {
	case .D1:
		binding = .Texture_1d_Storage_Image
	case .D2:
		binding = .Texture_2d_Storage_Image
	case .D2_Array:
		binding = .Texture_2d_Array_Storage_Image
	case .D3:
		binding = .Texture_3d_Storage_Image
	case:
		panic("Invalid binding type for storage textures (`.Cube` and `.Cube_Array` are disallowed).")
	}
	
	updates := vk.WriteDescriptorSet {
		sType		= .WRITE_DESCRIPTOR_SET,
		dstSet		= metadata.vk.descriptor_set,
		dstBinding	= cast(u32)binding,
		dstArrayElement	= 0,
		descriptorCount	= cast(u32)len(textures_infos),
		descriptorType	= .STORAGE_IMAGE,
		pImageInfo	= raw_data(textures_infos),
	}
	vk.UpdateDescriptorSets(vk_device, 1, &updates, 0, nil)

	return nil
}

vk_set_sampler_set :: proc(metadata: ^_Resource_Set_Metadata) -> Result {
	sampler_infos := make([]vk.DescriptorImageInfo, len(metadata.sampler_set), _temp_allocator) or_return
	for sampler, i in metadata.sampler_set {
		sampler_metadata := _metadata_of(sampler) or_return

		sampler_infos[i] = {
			sampler		= sampler_metadata.vk.sampler,
			imageLayout	= .GENERAL,
		}
	}

	update := vk.WriteDescriptorSet {
		sType		= .WRITE_DESCRIPTOR_SET,
		dstSet		= metadata.vk.descriptor_set,
		dstBinding	= cast(u32)vk_Descriptor_Binding.Sampler,
		dstArrayElement	= 0,
		descriptorCount	= cast(u32)len(sampler_infos),
		descriptorType	= .SAMPLER,
		pImageInfo	= raw_data(sampler_infos),
	}
	vk.UpdateDescriptorSets(vk_device, 1, &update, 0, nil)

	return nil
}


