package gfx

import "base:runtime"
import "core:slice"
import vk "vendor:vulkan"

vk_Surface_Metadata :: struct {
	surface:	vk.SurfaceKHR,
	swapchain:	vk.SwapchainKHR,

	images:		[]vk.Image,
	image_views:	[]vk.ImageView,

	// Semaphores used foor presentation.
	present_semaphores:		[]vk.Semaphore,
	has_image_been_initialized:	[]bool,
	image_available_semaphores:	[]vk.Semaphore,
	next_image_available_semaphore:	int,
}

vk_supported_formats_for_target :: proc(
	descriptor: Surface_Descriptor,
	allocator: runtime.Allocator,
) -> (formats: []Pixel_Format, res: Result) {

	surface := vk_create_surface_from_descriptor(descriptor) or_return
	defer vk_destroy_surface_and_restore_target(surface, descriptor.target)

	supports_presentation: b32
	vk.GetPhysicalDeviceSurfaceSupportKHR(
		vk_physical_device, vk_device_info.default_queue_family, surface, &supports_presentation,
	)
	if !supports_presentation {
		return
	}

	format_count: u32
	vk_call(vk.GetPhysicalDeviceSurfaceFormatsKHR(vk_physical_device, surface, &format_count, nil)) or_return
	vk_formats := make([]vk.SurfaceFormatKHR, format_count, _temp_allocator) or_return
	vk_call(vk.GetPhysicalDeviceSurfaceFormatsKHR(
		vk_physical_device, surface, &format_count, raw_data(vk_formats)),
	) or_return

	selected_formats := make([dynamic]Pixel_Format, 0, format_count, allocator) or_return
	for format in vk_formats {
		if format.colorSpace != .SRGB_NONLINEAR {
			continue
		}

		pixel_format := vk_format_to_gfx_pixel_format(format.format)
		if pixel_format == .None {
			continue
		}

		append(&selected_formats, pixel_format)
	}

	return selected_formats[:], nil
}

vk_create_surface :: proc(metadata: ^_Surface_Metadata, descriptor: Surface_Descriptor) -> Result {
	surface := vk_create_surface_from_descriptor(descriptor) or_return
	
	present_modes_count: u32
	vk_call(vk.GetPhysicalDeviceSurfacePresentModesKHR(vk_physical_device, surface, &present_modes_count, nil)) or_return
	present_modes := make([]vk.PresentModeKHR, present_modes_count, _temp_allocator) or_return
	vk_call(vk.GetPhysicalDeviceSurfacePresentModesKHR(vk_physical_device, surface, &present_modes_count, raw_data(present_modes))) or_return

	swapchain_info := vk_surface_descriptor_to_vk_swapchain_info(
		descriptor,
		surface,
		present_modes,
		{},
	)
	swapchain: vk.SwapchainKHR
	vk_call(vk.CreateSwapchainKHR(vk_device, &swapchain_info, nil, &swapchain)) or_return

	image_count: u32
	vk_call(vk.GetSwapchainImagesKHR(vk_device, swapchain, &image_count, nil)) or_return
	images := make([]vk.Image, image_count, _generic_allocator) or_return
	vk_call(vk.GetSwapchainImagesKHR(vk_device, swapchain, &image_count, raw_data(images))) or_return

	views := make([]vk.ImageView, image_count, _generic_allocator) or_return
	for &view, i in views {
		view_info := vk.ImageViewCreateInfo {
			sType			= .IMAGE_VIEW_CREATE_INFO,
			image			= images[i],
			viewType		= .D2,
			format			= vk_PIXEL_FORMAT_TO_VK[descriptor.format],
			subresourceRange	= {
				aspectMask	= { .COLOR },
				baseMipLevel	= 0,
				levelCount	= 1,
				baseArrayLayer	= 0,
				layerCount	= 1,
			},
		}

		vk_call(vk.CreateImageView(vk_device, &view_info, nil, &view)) or_return
	}

	present_semaphores := make([]vk.Semaphore, image_count, _generic_allocator) or_return
	for &semaphore in present_semaphores {
		semaphore_info := vk.SemaphoreCreateInfo {
			sType	= .SEMAPHORE_CREATE_INFO,
		}
		vk_call(vk.CreateSemaphore(vk_device, &semaphore_info, nil, &semaphore)) or_return
	}

	acquire_semaphore_count := max(image_count, cast(u32)descriptor.frames_in_flight)
	image_available_semaphores := make([]vk.Semaphore, acquire_semaphore_count, _generic_allocator) or_return
	for &semaphore in image_available_semaphores {
		semaphore_info := vk.SemaphoreCreateInfo {
			sType	= .SEMAPHORE_CREATE_INFO,
		}
		vk_call(vk.CreateSemaphore(vk_device, &semaphore_info, nil, &semaphore)) or_return
	}

	has_image_been_initialized := make([]bool, image_count, _generic_allocator) or_return


	metadata.vk.surface	= surface
	metadata.vk.swapchain	= swapchain
	metadata.vk.images	= images
	metadata.vk.image_views	= views
	metadata.vk.present_semaphores		= present_semaphores
	metadata.vk.image_available_semaphores	= image_available_semaphores
	metadata.vk.has_image_been_initialized	= has_image_been_initialized

	return nil
}

vk_destroy_surface :: proc(metadata: ^_Surface_Metadata) {

	vk.QueueWaitIdle(_queues[.Default].vk.queue)

	for view in metadata.vk.image_views {
		vk.DestroyImageView(vk_device, view, nil)
	}
	for semaphore in metadata.vk.present_semaphores {
		vk.DestroySemaphore(vk_device, semaphore, nil)
	}
	for semaphore in metadata.vk.image_available_semaphores {
		vk.DestroySemaphore(vk_device, semaphore, nil)
	}

	vk.DestroySwapchainKHR(vk_device, metadata.vk.swapchain, nil)
	vk_destroy_surface_and_restore_target(metadata.vk.surface, metadata.target)

	delete(metadata.vk.images, _generic_allocator)
	delete(metadata.vk.image_views, _generic_allocator)
	delete(metadata.vk.present_semaphores, _generic_allocator)
	delete(metadata.vk.image_available_semaphores)
	delete(metadata.vk.has_image_been_initialized, _generic_allocator)
}

vk_present :: proc(
	queue_metadata:		^_Queue_Metadata,
	surface_metadata:	^_Surface_Metadata,
	view_metadata:		^_View_Metadata,
	waits:			[]_Semaphore_Wait,
) -> Result {

	image_index := view_metadata.vk.swapchain_image_index
	image_semaphore := surface_metadata.vk.present_semaphores[image_index]

	semaphore_waits := make([]vk.SemaphoreSubmitInfo, len(waits), _temp_allocator) or_return
	for wait, i in waits {
		semaphore_waits[i] = vk.SemaphoreSubmitInfo {
			sType		= .SEMAPHORE_SUBMIT_INFO,
			semaphore	= wait.semaphore.vk.semaphore,
			value		= cast(u64)wait.value,
		}
	}

	semaphore_signal := vk.SemaphoreSubmitInfo {
		sType		= .SEMAPHORE_SUBMIT_INFO,
		semaphore	= image_semaphore,
	}

	submit_info := vk.SubmitInfo2 {
		sType				= .SUBMIT_INFO_2,
		waitSemaphoreInfoCount		= cast(u32)len(semaphore_waits),
		pWaitSemaphoreInfos		= raw_data(semaphore_waits),
		signalSemaphoreInfoCount	= 1,
		pSignalSemaphoreInfos		= &semaphore_signal,
	}
	vk_call(vk.QueueSubmit2KHR(queue_metadata.vk.queue, 1, &submit_info, 0)) or_return

	present_info := vk.PresentInfoKHR {
		sType			= .PRESENT_INFO_KHR,
		waitSemaphoreCount	= 1,
		pWaitSemaphores		= &image_semaphore,
		swapchainCount		= 1,
		pSwapchains		= &surface_metadata.vk.swapchain,
		pImageIndices		= &image_index,
	}
	vk_call(vk.QueuePresentKHR(queue_metadata.vk.queue, &present_info)) or_return

	return nil
}
	
vk_acquire_surface_view :: proc(metadata: ^_Surface_Metadata, view_metadata: ^_View_Metadata) -> Result {

	semaphore_index := metadata.vk.next_image_available_semaphore % len(metadata.vk.image_available_semaphores)
	metadata.vk.next_image_available_semaphore += 1
	semaphore := metadata.vk.image_available_semaphores[semaphore_index]

	image_index: u32
	res := vk.AcquireNextImageKHR(
		vk_device,
		metadata.vk.swapchain,
		max(u64),
		semaphore,
		{},
		&image_index,
	)
	if res != .SUCCESS && res != .SUBOPTIMAL_KHR {
		return .Surface_Unavailable
	}

	view_metadata.vk.view				= metadata.vk.image_views[image_index]
	view_metadata.vk.swapchain_image_index		= image_index
	view_metadata.vk.swapchain_image_semaphore	= semaphore
	
	return nil
}

vk_resize_surface :: proc(metadata: ^_Surface_Metadata, dimensions: [2]int) -> Result {
	
	vk_destroy_surface(metadata)
	vk_create_surface(metadata, metadata.desc) or_return

	return nil
}

vk_destroy_surface_view :: proc(surface_metadata: ^_Surface_Metadata, view_metadata: ^_View_Metadata) -> Result {
	return nil
}

vk_surface_descriptor_to_vk_swapchain_info :: proc(
	descriptor:			Surface_Descriptor,
	surface:			vk.SurfaceKHR,
	supported_present_modes:	[]vk.PresentModeKHR,
	old_swapchain:			vk.SwapchainKHR,
) -> (info: vk.SwapchainCreateInfoKHR) {
	
	surface_capabilities: vk.SurfaceCapabilitiesKHR
	vk_call(vk.GetPhysicalDeviceSurfaceCapabilitiesKHR(vk_physical_device, surface, &surface_capabilities))

	// NOTE: FIFO is guaranteed to be present.
	present_mode := vk.PresentModeKHR.FIFO
	switch descriptor.type {
	case .Immediate:
		if slice.contains(supported_present_modes, vk.PresentModeKHR.IMMEDIATE) {
			present_mode = .IMMEDIATE
		}

	case .V_Sync:
		if slice.contains(supported_present_modes, vk.PresentModeKHR.MAILBOX) {
			present_mode = .MAILBOX
		}
	}

	info.sType			= .SWAPCHAIN_CREATE_INFO_KHR
	info.surface			= surface
	info.minImageCount		= min(cast(u32)descriptor.frames_in_flight, surface_capabilities.maxImageCount)
	info.imageArrayLayers		= 1
	info.imageFormat		= vk_PIXEL_FORMAT_TO_VK[descriptor.format]
	info.imageColorSpace		= .SRGB_NONLINEAR
	info.imageExtent		= {
		cast(u32)descriptor.dimensions.x, cast(u32)descriptor.dimensions.y,
	}
	info.imageUsage			= { .COLOR_ATTACHMENT }
	info.imageSharingMode		= .EXCLUSIVE
	info.queueFamilyIndexCount	= 1
	info.pQueueFamilyIndices	= &vk_device_info.default_queue_family
	info.presentMode		= present_mode
	info.preTransform		= { .IDENTITY }
	info.compositeAlpha		= { .OPAQUE }
	info.oldSwapchain		= old_swapchain

	return
}

