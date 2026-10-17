#+build windows
package vicixdev_gfx

/*
Copyright (c) 2026 Vicix (https://github.com/vicixdev)

This Source Code Form is subject to the terms of the Mozilla Public
License, v. 2.0. If a copy of the MPL was not distributed with this
file, You can obtain one at https://mozilla.org/MPL/2.0/.
*/

import win "core:sys/windows"
import vk "vendor:vulkan"

_vk_create_surface_from_descriptor :: proc(descriptor: Surface_Descriptor) -> (surface: vk.SurfaceKHR, res: Result) {
	assert(_vk_supports_win32_surfaces)

	target, is_win32_target := descriptor.target.(Surface_HWND_Target)
	if !is_win32_target {
		return {}, .Invalid_Descriptor
	}

	h_instance := cast(vk.HINSTANCE)cast(uintptr)win.GetWindowLongPtrW(cast(win.HWND)target.h_wnd, win.GWLP_HINSTANCE)

	surface_descriptor := vk.Win32SurfaceCreateInfoKHR{
		sType		= .WIN32_SURFACE_CREATE_INFO_KHR,
		hwnd		= cast(vk.HWND)target.h_wnd,
		hinstance	= h_instance,
	}
	_vk_call(vk.CreateWin32SurfaceKHR(_vk_instance, &surface_descriptor, nil, &surface)) or_return

	return
}

_vk_destroy_surface_and_restore_target :: proc(surface: vk.SurfaceKHR, target: Surface_Target) {
	vk.DestroySurfaceKHR(_vk_instance, surface, nil)
}


