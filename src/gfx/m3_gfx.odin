#+build darwin
package gfx

// import hm "core:container/handle_map"

m3_init :: proc() {
	// hm.dynamic_init(&m3_command_buffers, context.allocator)
}

m3_fini :: proc() {
	when ODIN_DEBUG {
		m3_end_tracing()
	}

	for device in _available_devices {
		device._platform.m3.device->release()
	}
}

