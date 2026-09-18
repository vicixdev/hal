#+build darwin
package vicixdev_gfx

/*
This Source Code Form is subject to the terms of the Mozilla Public
License, v. 2.0. If a copy of the MPL was not distributed with this
file, You can obtain one at https://mozilla.org/MPL/2.0/.
*/

import vk "vendor:vulkan"
import NS "core:sys/darwin/Foundation"

_vk_create_surface_from_descriptor :: proc(descriptor: Surface_Descriptor) -> (surface: vk.SurfaceKHR, res: Result) {
	assert(_vk_supports_metal_surfaces)

	view := cast(^NS.View)descriptor.target.(Surface_Cocoa_Target).ns_view

	layer := _m3_create_metal_layer_from_descriptor(descriptor)

	view->setWantsLayer(true)
	view->setLayer(layer)

	instance_info := vk.MetalSurfaceCreateInfoEXT {
		sType	= .METAL_SURFACE_CREATE_INFO_EXT,
		pLayer	= cast(^vk.CAMetalLayer)layer,
	}
	_vk_call(vk.CreateMetalSurfaceEXT(_vk_instance, &instance_info, nil, &surface)) or_return

	return
}

_vk_destroy_surface_and_restore_target :: proc(surface: vk.SurfaceKHR, target: Surface_Target) {

	vk.DestroySurfaceKHR(_vk_instance, surface, nil)

	view := cast(^NS.View)target.(Surface_Cocoa_Target).ns_view
	view->layer()->release()

	view->setWantsLayer(false)
	view->setLayer(nil)
}

