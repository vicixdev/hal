#+build darwin
package gfx

import "core:log"
import "core:os"
import hm "core:container/handle_map"
import NS "core:sys/darwin/Foundation"
import MTL "vendor:darwin/Metal"

_device:	^MTL.Device
_is_tracing:	bool
_sampler:	^MTL.SamplerState

_init :: proc() {
	_device = MTL.CreateSystemDefaultDevice()
	_queue = _device->newCommandQueue()

	hm.dynamic_init(&_buffers, context.allocator)
	hm.dynamic_init(&_textures, context.allocator)
	hm.dynamic_init(&_views, context.allocator)
	hm.dynamic_init(&_command_buffers, context.allocator)

	sampler_desc := MTL.SamplerDescriptor.alloc()->init()
	defer sampler_desc->release()

	sampler_desc->setMagFilter(.Nearest)
	sampler_desc->setMinFilter(.Nearest)
	sampler_desc->setMipFilter(.Nearest)
	sampler_desc->setSupportArgumentBuffers(true)

	_sampler = _device->newSamplerState(sampler_desc)

	when ODIN_DEBUG {
		_begin_tracing()
	}
}

_fini :: proc() {
	when ODIN_DEBUG {
		_end_tracing()
	}

	hm.dynamic_destroy(&_buffers)
	hm.dynamic_destroy(&_textures)
	hm.dynamic_destroy(&_views)

	_device->release()
}

_begin_tracing :: proc() {
	capture_manager := MTL.CaptureManager.sharedCaptureManager()
	if !capture_manager->supportsDestination(.GPUTraceDocument) {
		log.info("Could not start a capture. Try starting the application with the following environment variables:")
		log.info("\t- MTL_DEBUG_LAYER=1")
		log.info("\t- MTL_CAPTURE_ENABLED=1")
		return
	}

	if os.exists("/tmp/hal.gputrace") {
		err := os.remove_all("/tmp/hal.gputrace")
		if err != nil {
			log.warnf("Could not start a capture: Could not remove the previous trace file (got error: %v):", err)
			return
		}
	}

	capture_desc := MTL.CaptureDescriptor.alloc()->init()
	defer capture_desc->release()

	output_url := NS.URL.alloc()->initFileURLWithPath(NS.AT("/tmp/hal.gputrace"))
	defer output_url->release()

	capture_desc->setCaptureObject(_device)
	capture_desc->setDestination(.GPUTraceDocument)
	capture_desc->setOutputURL(output_url)

	capture_ok, capture_err := capture_manager->startCaptureWithDescriptor(capture_desc)
	if !capture_ok {
		log.warnf(
			"Could not start a capture: %s - %s",
			capture_err->localizedFailureReason()->odinString(),
			capture_err->localizedDescription()->odinString(),
		)
	}

	_is_tracing = true
}

_end_tracing :: proc() {
	if !_is_tracing {
		return
	}

	capture_manager := MTL.CaptureManager.sharedCaptureManager()
	capture_manager->stopCapture()
}

