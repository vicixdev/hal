#+build darwin
package gfx

import "core:log"
import "core:os"
import hm "core:container/handle_map"
import NS "core:sys/darwin/Foundation"
import MTL "vendor:darwin/Metal"

m3_device:	^MTL.Device
m3_is_tracing:	bool
m3_sampler:	^MTL.SamplerState

m3_init :: proc() {
	m3_device = MTL.CreateSystemDefaultDevice()
	m3_queue = m3_device->newCommandQueue()

	hm.dynamic_init(&m3_command_buffers, context.allocator)

	sampler_desc := MTL.SamplerDescriptor.alloc()->init()
	defer sampler_desc->release()

	sampler_desc->setMagFilter(.Nearest)
	sampler_desc->setMinFilter(.Nearest)
	sampler_desc->setMipFilter(.Nearest)
	sampler_desc->setSupportArgumentBuffers(true)

	m3_sampler = m3_device->newSamplerState(sampler_desc)

	when ODIN_DEBUG {
		m3_begin_tracing()
	}
}

m3_fini :: proc() {
	when ODIN_DEBUG {
		m3_end_tracing()
	}

	m3_device->release()
}

m3_begin_tracing :: proc() {
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

	capture_desc->setCaptureObject(m3_device)
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

	m3_is_tracing = true
}

m3_end_tracing :: proc() {
	if !m3_is_tracing {
		return
	}

	capture_manager := MTL.CaptureManager.sharedCaptureManager()
	capture_manager->stopCapture()
}

