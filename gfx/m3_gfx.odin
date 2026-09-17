/*
This Source Code Form is subject to the terms of the Mozilla Public
License, v. 2.0. If a copy of the MPL was not distributed with this
file, You can obtain one at https://mozilla.org/MPL/2.0/.
*/

#+build darwin
package vicixdev_gfx

import NS "core:sys/darwin/Foundation"

m3_init :: proc() -> Result {
	return nil
}

m3_pre_fini :: proc() {
	NS.scoped_autoreleasepool()

	when ENABLE_TRACING {
		m3_end_tracing()
	}

	if _m3_residency_set != nil {
		_m3_residency_set->release()
		_m3_residency_set = nil
	}

	if m3_resource_set_heap != nil {
		m3_resource_set_heap->release()
		m3_resource_set_heap = nil
	}
}

m3_fini :: proc() {}

