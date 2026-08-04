package gfx

import "base:runtime"
import "core:strings"
import "core:mem"
import "core:log"
import "core:os"
import NS "core:sys/darwin/Foundation"
import MTL "vendor:darwin/Metal"

m3_Device_Info :: struct {
	device:	^MTL.Device,
}

m3_device:	^MTL.Device
m3_is_tracing:	bool

m3_enumerate_devices :: proc(
	allocator: runtime.Allocator,
) -> (available_devices: []Device_Info, res:Result) {

	mtl_devices := MTL.CopyAllDevices()
	defer mtl_devices->release()

	devices := make([dynamic]Device_Info, 0, mtl_devices->count(), allocator=allocator) or_return

	device_id: Device_Id
	for i: NS.UInteger; i < mtl_devices->count(); i += 1 {
		device := mtl_devices->objectAs(i, ^MTL.Device)

		if !m3_is_device_suitable(device) {
			continue
		}

		device->retain()

		append(
			&devices,
			Device_Info {
				id		= device_id,
				name		= strings.clone(device->name()->odinString(), context.allocator),
				type		= .Integrated,
				limits		= {
					min_allocation_size	= 16 * mem.Kilobyte,
					// NOTE: 16 kilobytes is the page size in apple silicon hardware.
					allocation_alignment	= 16 * mem.Kilobyte,
				},
				properties	= {
					host_accessible_device_memory	= true,
					fast_compute_render_interleaving = false,
					coherent_memory			= true,
					transfer_queue			= true,
				},
				_platform	= {
					m3	= {
						device = device,
					},
				},
			},
		)

		device_id += 1
	}

	return devices[:], nil
}

m3_select_device :: proc(device: Device_Id) -> Result {
	m3_device = _available_devices[device]._platform.m3.device
	m3_queue = m3_device->newCommandQueue()

	when ODIN_DEBUG {
		m3_begin_tracing()
	}

	return nil
}

m3_is_device_suitable :: proc(device: ^MTL.Device) -> bool {
	return device->supportsFamily(.Metal3) &&
		device->hasUnifiedMemory()
}

m3_begin_tracing :: proc() {
	m3_begin_tracing_on_device(m3_device)
}

m3_begin_tracing_on_device :: proc(device: ^MTL.Device) {
	if m3_is_tracing {
		log.errorf("Could not start a capture. Another capture is already active.")
	}

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

	capture_desc->setCaptureObject(device)
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

