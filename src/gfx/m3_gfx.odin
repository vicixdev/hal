#+build darwin
package gfx

import NS "core:sys/darwin/Foundation"

m3_init :: proc() -> Result {
	return nil
}

m3_pre_fini :: proc() {
	NS.scoped_autoreleasepool()

	when ENABLE_TRACING {
		m3_end_tracing()
	}
}

m3_fini :: proc() {}

