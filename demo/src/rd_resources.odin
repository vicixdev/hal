package main

import "base:runtime"
import "root:gfx"

_rd_Resource_Manager_Views :: struct {
	views:		[dynamic]gfx.View,
	free_list:	[dynamic]int,
	did_change:	[3]bool,
}

_rd_Resource_Manager_Samplers :: struct {
	samplers:	[dynamic]gfx.Sampler,
	free_list:	[dynamic]int,
	did_change:	[3]bool,
}

rd_Resource_Manager :: struct {
	allocator:	runtime.Allocator,

	resource_sets:	[3]gfx.Resource_Set,
	current_frame:	int,

	sampled:	[gfx.View_Type]_rd_Resource_Manager_Views,
	storage:	[gfx.Storage_View_Type]_rd_Resource_Manager_Views,
	samplers:	_rd_Resource_Manager_Samplers,
}

rd_resource_manager :: proc() -> ^rd_Resource_Manager {
	@(static)
	resource_manager: rd_Resource_Manager

	return &resource_manager
}

rd_init_resource_manager :: proc(manager: ^rd_Resource_Manager) -> Result {
	for &resource_set in manager.resource_sets {
		resource_set = gfx.create_resource_set() or_return
	}

	return nil
}

rd_cycle_resource_manager :: proc(manager: ^rd_Resource_Manager) {
	manager.current_frame += 1
	manager.current_frame %= len(manager.resource_sets)
}

rd_acquire_texture_resource_id :: proc(
	manager: ^rd_Resource_Manager,
	type: gfx.View_Type,
	view: gfx.View,
) -> (id: int) {

	data := &manager.sampled[type]

	had_free_id: bool
	if id, had_free_id = pop_safe(&data.free_list); had_free_id {
		data.views[id] = view
	} else {
		id = len(data.views)
		append(&data.views, view)
	}

	data.did_change = true

	return id
}

rd_release_texture_resource_id :: proc(manager: ^rd_Resource_Manager, type: gfx.View_Type, id: int) {
	append(&manager.sampled[type].free_list, id)
}

rd_acquire_storage_texture_resource_id :: proc(
	manager: ^rd_Resource_Manager,
	type: gfx.Storage_View_Type,
	view: gfx.View,
) -> (id: int) {

	data := &manager.storage[type]

	had_free_id: bool
	if id, had_free_id = pop_safe(&data.free_list); had_free_id {
		data.views[id] = view
	} else {
		id = len(data.views)
		append(&data.views, view)
	}

	data.did_change = true

	return id
}

rd_release_storage_texture_resource_id :: proc(manager: ^rd_Resource_Manager, type: gfx.Storage_View_Type, id: int) {
	append(&manager.storage[type].free_list, id)
}

rd_acquire_sampler_resource_id :: proc(
	manager: ^rd_Resource_Manager,
	sampler: gfx.Sampler,
) -> (id: int) {

	data := &manager.samplers

	had_free_id: bool
	if id, had_free_id = pop_safe(&data.free_list); had_free_id {
		data.samplers[id] = sampler
	} else {
		id = len(data.samplers)
		append(&data.samplers, sampler)
	}

	data.did_change = true

	return id
}

rd_release_sampler_resource_id :: proc(manager: ^rd_Resource_Manager, id: int) {
	append(&manager.samplers.free_list, id)
}

rd_acquire_resource_id :: proc {
	rd_acquire_texture_resource_id,
	rd_acquire_storage_texture_resource_id,
	rd_acquire_sampler_resource_id,
}

rd_apply_resource_manager_updates :: proc(manager: ^rd_Resource_Manager) {

	resource_set := rd_current_resource_set_of(manager)

	for &sampled, type in manager.sampled {
		if !sampled.did_change[manager.current_frame] {
			continue
		}

		gfx.set_texture_set(resource_set, type, sampled.views[:])
		sampled.did_change[manager.current_frame] = false
	}

	for &storage, type in manager.storage {
		if !storage.did_change[manager.current_frame] {
			continue
		}

		gfx.set_storage_texture_set(resource_set, type, storage.views[:])
		storage.did_change[manager.current_frame] = false
	}

	if manager.samplers.did_change[manager.current_frame] {
		gfx.set_sampler_set(resource_set, manager.samplers.samplers[:])
		manager.samplers.did_change[manager.current_frame] = false
	}
}

rd_current_resource_set_of :: proc(manager: ^rd_Resource_Manager) -> gfx.Resource_Set {
	return manager.resource_sets[manager.current_frame]
}

