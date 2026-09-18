#+build darwin
package vicixdev_gfx

/*
This Source Code Form is subject to the terms of the Mozilla Public
License, v. 2.0. If a copy of the MPL was not distributed with this
file, You can obtain one at https://mozilla.org/MPL/2.0/.
*/

import "base:runtime"
import "core:slice"
import CF "core:sys/darwin/CoreFoundation"
import NS "core:sys/darwin/Foundation"
import CA "vendor:darwin/QuartzCore"

_m3_Surface_Metadata :: struct {
	layer:	^CA.MetalLayer,
	view:	^NS.View,
}

_m3_supported_formats_for_target :: proc(
	descriptor: Surface_Descriptor,
	allocator: runtime.Allocator,
) -> (formats: []Pixel_Format, res: Result) {
	NS.scoped_autoreleasepool()

	formats = slice.clone(_m3_SUPPORTED_PRESENTATION_FORMATS, allocator) or_return

	return
}

_m3_create_surface :: proc(metadata: ^_Surface_Metadata, descriptor: Surface_Descriptor) -> Result {
	NS.scoped_autoreleasepool()
	
	view := cast(^NS.View)descriptor.target.(Surface_Cocoa_Target).ns_view
	layer := _m3_create_metal_layer_from_descriptor(descriptor)

	view->retain()
	view->setWantsLayer(true)
	view->setLayer(layer)

	metadata.m3.layer = layer
	metadata.m3.view = view

	return nil
}

_m3_destroy_surface :: proc(metadata: ^_Surface_Metadata) {
	NS.scoped_autoreleasepool()

	metadata.m3.view->setWantsLayer(false)
	metadata.m3.view->setLayer(nil)
	metadata.m3.view->release()

	metadata.m3.layer->release()
}

_m3_resize_surface :: proc(metadata: ^_Surface_Metadata, dimensions: [2]int) -> Result {
	metadata.m3.layer->setDrawableSize({
		cast(CF.CGFloat)dimensions.x, cast(CF.CGFloat)dimensions.y,
	})

	return nil
}

_m3_acquire_surface_view :: proc(metadata: ^_Surface_Metadata, view_metadata: ^_View_Metadata, semaphore_metadata: ^_Semaphore_Metadata) -> Result {
	NS.scoped_autoreleasepool()

	drawable := metadata.m3.layer->nextDrawable()
	if drawable == nil {
		return .Surface_Unavailable
	}

	drawable->retain()
	view_metadata.m3.drawable	= drawable
	view_metadata.m3.view		= drawable->texture()

	return nil
}

_m3_destroy_surface_view :: proc(surface_metadata: ^_Surface_Metadata, view_metadata: ^_View_Metadata) -> Result {

	view_metadata.m3.drawable->release()

	return nil
}

_m3_present :: proc(
	queue_metadata:		^_Queue_Metadata,
	surface_metadata:	^_Surface_Metadata,
	view_metadata:		^_View_Metadata,
	waits:			[]_Semaphore_Wait,
) -> (res: Result) {
	NS.scoped_autoreleasepool()
	
	command_buffer := queue_metadata.m3.queue->commandBuffer()

	for wait in waits {
		_m3_emit_wait_semaphore(command_buffer, wait.semaphore, wait.value)
	}

	command_buffer->presentDrawable(view_metadata.m3.drawable)
	command_buffer->commit()

	return nil
}

_m3_create_metal_layer_from_descriptor :: proc(descriptor: Surface_Descriptor) -> (layer: ^CA.MetalLayer) {
	layer = CA.MetalLayer.layer()

	layer->setDisplaySyncEnabled(descriptor.type == .V_Sync ? true : false)
	layer->setDrawableSize({
		cast(CF.CGFloat)descriptor.dimensions.x, cast(CF.CGFloat)descriptor.dimensions.y,
	})
	layer->setDevice(_m3_device)
	layer->setMaximumDrawableCount(cast(NS.UInteger)descriptor.frames_in_flight)
	layer->setFramebufferOnly(true)

	if descriptor.format != .None {
		layer->setPixelFormat(_m3_PIXEL_FORMAT_TO_MTL[descriptor.format])
	}

	return
}

// Source: https://developer.apple.com/documentation/quartzcore/cametallayer/pixelformat
@(rodata)
_m3_SUPPORTED_PRESENTATION_FORMATS := []Pixel_Format {
	.BGRA8_Unorm,
	.BGRA8_Srgb,
	.RGBA16_Float,
	.RGB10_A2_Unorm,
}

