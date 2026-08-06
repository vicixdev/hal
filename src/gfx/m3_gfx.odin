#+build darwin
package gfx

m3_init :: proc() -> Result {
	return nil
}

m3_fini :: proc() {
	when ODIN_DEBUG {
		m3_end_tracing()
	}

	for device in _available_devices {
		device._platform.m3.device->release()
	}
}

