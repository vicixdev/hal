#+build darwin
package gfx

import MTL "vendor:darwin/Metal"

m3_init :: proc() -> Result {
	m3_residency_set = make([dynamic]^MTL.Heap, _generic_allocator)
	m3_residency_set_handles = make([dynamic]Handle, _generic_allocator)

	return nil
}

m3_pre_fini :: proc() {
	when ENABLE_TRACING {
		m3_end_tracing()
	}
}

m3_fini :: proc() {
	for device in _available_devices {
		device._platform.m3.device->release()
	}

	delete(m3_residency_set)
	delete(m3_residency_set_handles)
}

