#+build darwin
package gfx

m3_init :: proc() -> Result {
	return nil
}

m3_pre_fini :: proc() {
	when ENABLE_TRACING {
		m3_end_tracing()
	}
}

m3_fini :: proc() {}

