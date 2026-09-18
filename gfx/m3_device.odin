#+build darwin
package vicixdev_gfx

/*
This Source Code Form is subject to the terms of the Mozilla Public
License, v. 2.0. If a copy of the MPL was not distributed with this
file, You can obtain one at https://mozilla.org/MPL/2.0/.
*/

import "base:runtime"
import "core:mem"
import "core:log"
import "core:os"
import "core:strings"
import NS "core:sys/darwin/Foundation"
import MTL "vendor:darwin/Metal"
import MTLe "darwext/Metal"

_m3_Device_Info :: struct {
	device:	^MTL.Device,
}

_m3_device:	^MTL.Device
_m3_is_tracing:	bool

_m3_resource_set_heap:	^MTL.Heap

_m3_enumerate_devices :: proc(
	allocator: runtime.Allocator,
) -> (available_devices: []Device_Info, res:Result) {
	NS.scoped_autoreleasepool()

	mtl_devices := MTL.CopyAllDevices()
	defer mtl_devices->release()

	devices := make([dynamic]Device_Info, 0, mtl_devices->count(), allocator=allocator) or_return

	device_id: Device_Id
	for i: NS.UInteger; i < mtl_devices->count(); i += 1 {
		device := mtl_devices->objectAs(i, ^MTL.Device)

		if !_m3_is_device_suitable(device) {
			continue
		}

		device->retain()

		append(
			&devices,
			Device_Info {
				id		= device_id,
				name		= strings.clone(device->name()->odinString(), _global_allocator),
				driver		= "Metal",
				type		= .Integrated,
				limits		= {
					min_allocation_size	= 16 * mem.Kilobyte,
					// NOTE: 16 kilobytes is the page size in apple silicon hardware.
					allocation_alignment	= 16 * mem.Kilobyte,
				},
				properties	= {
					host_accessible_device_memory	= true,
					fast_compute_render_interleaving = false,
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

_m3_select_device :: proc(device: Device_Id) -> Result {
	NS.scoped_autoreleasepool()

	_m3_device = _available_devices[device]._platform.m3.device

	when ENABLE_TRACING {
		_m3_begin_tracing()
	}

	residency_set_descriptor := MTLe.ResidencySetDescriptor.alloc()->init()
	defer residency_set_descriptor->release()

	residency_set_descriptor->setInitialCapacity(128)
	_m3_residency_set = MTLe.Device_newResidencySetWithDescriptor(auto_cast _m3_device, residency_set_descriptor, nil)
	if _m3_residency_set == nil {
		return .Generic_Backend_Error
	}

	_m3_create_resource_set_heap() or_return

	return nil
}

_m3_is_device_suitable :: proc(device: ^MTL.Device) -> bool {
	return device->supportsFamily(.Metal3) &&
		device->hasUnifiedMemory()
}

_m3_begin_tracing :: proc() {
	_m3_begin_tracing_on_device(_m3_device)
}

_m3_begin_tracing_on_device :: proc(device: ^MTL.Device) {
	NS.scoped_autoreleasepool()

	if _m3_is_tracing {
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

	_m3_is_tracing = true
}

_m3_end_tracing :: proc() {
	if !_m3_is_tracing {
		return
	}

	capture_manager := MTL.CaptureManager.sharedCaptureManager()
	capture_manager->stopCapture()
}

_m3_create_resource_set_heap :: proc() -> Result {
	heap_desc := MTL.HeapDescriptor.alloc()->init()
	defer heap_desc->release()

	heap_desc->setResourceOptions({ .CPUCacheModeWriteCombined, .HazardTrackingModeUntracked })
	heap_desc->setSize(8 * mem.Megabyte)
	heap_desc->setStorageMode(.Shared)
	heap_desc->setType(.Automatic)

	_m3_resource_set_heap = _m3_device->newHeap(heap_desc)
	if _m3_resource_set_heap == nil {
		return .Out_Of_Gpu_Memory
	}

	_m3_residency_set->addAllocation(_m3_resource_set_heap)
	_m3_residency_set->commit()

	return nil
}

