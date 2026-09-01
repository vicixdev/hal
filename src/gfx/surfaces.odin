package gfx

import "base:runtime"
import "core:sync"
import "core:slice"
import hm "core:container/handle_map"

Surface :: distinct Handle

Surface_Type :: enum {
	Immediate,
	V_Sync,
}

Surface_Cocoa_Target :: struct {
	ns_view:	rawptr,
}

Surface_HWND_Target :: struct {
	h_wnd:		rawptr,
}

Surface_Wayland_Target :: struct {
	wl_display:	rawptr,
	wl_surface:	rawptr,
}

Surface_X11_Target :: struct {
	display:	rawptr,
	window:		rawptr,
}

Surface_Target :: union #no_nil {
	Surface_Cocoa_Target,
	Surface_HWND_Target,
	Surface_Wayland_Target,
	Surface_X11_Target,
}

Surface_Descriptor :: struct {
	type:			Surface_Type,
	format:			Pixel_Format,
	dimensions:		[2]int,
	frames_in_flight:	int,
	target:			Surface_Target,
}

_Surface_Metadata :: struct {
	handle:		Surface,

	using desc:	Surface_Descriptor,

	using platform:	struct #raw_union {
		m3:	m3_Surface_Metadata,
		vk:	vk_Surface_Metadata,
	},
}

_surfaces:		hm.Dynamic_Handle_Map(_Surface_Metadata, Surface)
_surfaces_mutex:	sync.RW_Mutex

supported_formats_of :: proc(
	descriptor:	Surface_Descriptor,
	allocator :=	context.temp_allocator,
	location :=	#caller_location,
) -> (formats: []Pixel_Format, res: Result) {

	_check_surface_target(descriptor.target, location) or_return

	when TARGET_API == .Vulkan {
		formats, res = vk_supported_formats_for_target(descriptor, allocator)
	} else when TARGET_API == .Metal_3 {
		formats, res = m3_supported_formats_for_target(descriptor, allocator)
	}

	_check_generic_backend_error(res, location) or_return

	return
}

create_surface :: proc(
	descriptor:	Surface_Descriptor,
	location :=	#caller_location,
) -> (surface: Surface, res: Result) {
	
	supported_formats := supported_formats_of(descriptor, _temp_allocator) or_return
	_check_condition(
		slice.contains(supported_formats, descriptor.format),
		.Invalid_Arguments,
		.Error,
		"Invalid surface format",
		"The specified surface format %v is not compatible with the list of supported formats for the " +
		"provided descriptor. Please query the supported surface formats with `gfx::supported_formats_of`.",
		descriptor.format,
		location=location,
	) or_return

	_check_surface_target(descriptor.target, location) or_return

	handle, metadata := _add_surface_metadata() or_return

	metadata.desc = descriptor

	when TARGET_API == .Vulkan {
		res = vk_create_surface(metadata, descriptor)
	} else {
		res = m3_create_surface(metadata, descriptor)
	}

	_check_generic_backend_error(res, location) or_return

	return handle, nil

}

destroy_surface :: proc(surface: Surface, location := #caller_location) {

	metadata, metadata_res := _metadata_of(surface)
	if metadata_res != nil do return

	when TARGET_API == .Vulkan {
		vk_destroy_surface(metadata)
	} else {
		m3_destroy_surface(metadata)
	}

	_remove_surface_metadata(surface)

}

acquire_surface_view :: proc(surface: Surface, location := #caller_location) -> (view: View, res: Result) {
	
	metadata, metadata_res := _metadata_of(surface)
	_check_surface_handle(metadata_res, surface, location)

	view_metadata: ^_View_Metadata
	view, view_metadata = _add_view_metadata() or_return
	defer if res != nil && res != .Surface_Unavailable do _remove_view_metadata(view)

	view_metadata.reference 	= surface
	view_metadata.next_view 	= view
	view_metadata.type		= .D2
	view_metadata.layer_count	= 1
	view_metadata.mip_count		= 1

	when TARGET_API == .Vulkan {
		res = vk_acquire_surface_view(metadata, view_metadata)
	} else {
		res = m3_acquire_surface_view(metadata, view_metadata)
	}

	if res == .Surface_Unavailable {
		return
	}

	_check_generic_backend_error(res, location) or_return

	return
}

present :: proc(
	queue:		Queue,
	view:		View,
	after:		..Semaphore_Wait,
	location :=	#caller_location,
) -> (res: Result) {
	
	_check_queue_validity(queue) or_return
	queue_metadata, _ := _metadata_of(queue)

	view_metadata, view_res := _metadata_of(view)
	_check_view_handle(view_res, view, location) or_return

	surface, is_referencing_surface := view_metadata.reference.(Surface)
	_check_condition(
		is_referencing_surface,
		.Invalid_View,
		.Error,
		"Invalid view",
		"Only views referencing a surface can be presented. View %v is referencing a texture.",
		view,
		location=location,
	) or_return

	surface_metadata, surface_res := _metadata_of(surface)
	_check_surface_handle(surface_res, surface, location) or_return

	_check_condition(
		view_metadata.used,
		.Invalid_View,
		.Warning,
		"Presenting unused view",
		"The view %v is being presented when it has not been used in a renderpass.",
		view,
		location=location,
	) or_return

	waits := make([]_Semaphore_Wait, len(after), _temp_allocator) or_return
	for wait, i in after {
		semaphore_metadata, semaphore_res := _metadata_of(wait.semaphore)
		_check_semaphore_handle(semaphore_res, wait.semaphore, location) or_return

		waits[i] = _Semaphore_Wait {
			semaphore	= semaphore_metadata,
			value		= wait.value,
		}
	}

	if sync.guard(&queue_metadata.emission_mutex) {
		when TARGET_API == .Vulkan {
			res = vk_present(queue_metadata, surface_metadata, view_metadata, waits)
		} else {
			res = m3_present(queue_metadata, surface_metadata, view_metadata, waits)
		}
	}

	_check_generic_backend_error(res, location) or_return

	_destroy_surface_view(view, location)

	return nil
}

resize_surface :: proc(surface: Surface, dimensions: [2]int, location := #caller_location) -> (res: Result) {
	
	metadata, surface_res := _metadata_of(surface)
	_check_surface_handle(surface_res, surface, location) or_return

	metadata.dimensions = dimensions

	wait_idle(.Default)
	if _device_info.properties.transfer_queue {
		wait_idle(.Transfer)
	}

	when TARGET_API == .Vulkan {
		res = vk_resize_surface(metadata, dimensions)
	} else {
		res = m3_resize_surface(metadata, dimensions)
	}

	res = _check_generic_backend_error(res, location)

	return
}

_destroy_surface_view :: proc(view: View, location := #caller_location) {

	view_metadata, view_res := _metadata_of(view)
	_check_view_handle(view_res, view, location)
	if view_res != nil do return

	surface := view_metadata.reference.(Surface)
	surface_metadata, surface_res := _metadata_of(surface)
	if surface_res != nil do return

	res: Result
	when TARGET_API == .Vulkan {
		res = vk_destroy_surface_view(surface_metadata, view_metadata)
	} else {
		res = m3_destroy_surface_view(surface_metadata, view_metadata)
	}

	_remove_view_metadata(view)

	_check_generic_backend_error(res, location)
}

_check_surface_target :: proc(target: Surface_Target, location: runtime.Source_Code_Location) -> Result {
	when ODIN_OS == .Darwin {
		_, is_cocoa_target := target.(Surface_Cocoa_Target)
		_check_condition(
			is_cocoa_target,
			.Invalid_Arguments,
			.Error,
			"Invalid surface target",
			"Only Cocoa surface targets can be used on macOS. Got target %v instead.",
			target,
			location=location,
		) or_return
	} else when ODIN_OS == .Windows {
		_, is_hwnd_target := target.(Surface_HWND_Target)
		_check_condition(
			is_hwnd_target,
			.Invalid_Arguments,
			.Error,
			"Invalid surface target",
			"Only HWND surface targets can be used on Windows. Got target %v instead.",
			target,
			location=location,
		) or_return
	} else {
		_, is_wayland_target := target.(Surface_Wayland_Target)
		_, is_x11_target := target.(Surface_X11_Target)
		_check_condition(
			is_wayland_target || is_x11_target,
			.Invalid_Arguments,
			.Error,
			"Invalid surface target",
			"Only Wayland or X11 surface targets can be used on *nix systems. Got target %v instead.",
			target,
			location=location,
		) or_return
	}

	return nil
}

_check_surface_handle :: proc(result: Result, surface: Surface, location: runtime.Source_Code_Location) -> Result {
	_check_result(
		result,
		.Warning,
		"Invalid resource handle",
		"Invalid surface handle (%v).",
		surface,
		location=location,
	) or_return
	return nil
}

_surface_metadata_of :: proc(surface: Surface) -> (^_Surface_Metadata, Result) {
	sync.shared_guard(&_surfaces_mutex)

	metadata, ok := hm.get(&_surfaces, surface)
	if !ok {
		return nil, .Invalid_Surface
	}
	
	return metadata, nil
}

_add_surface_metadata :: proc() -> (surface: Surface, metadata: ^_Surface_Metadata, res: Result) {
	sync.guard(&_surfaces_mutex)

	surface = hm.add(&_surfaces, _Surface_Metadata {}) or_return
	metadata = hm.get(&_surfaces, surface)

	return
}

_remove_surface_metadata :: proc(surface: Surface) {
	sync.guard(&_surfaces_mutex)

	hm.remove(&_surfaces, surface)
}


