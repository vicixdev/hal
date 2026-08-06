#+private
package gfx_tests

import "core:testing"
import gfx ".."

@(test)
init_fini :: proc(t: ^testing.T) {
	init_res := gfx.init({})
	testing.expect(t, init_res == nil)

	gfx.fini()
}

@(test)
supports_multi_init :: proc(t: ^testing.T) {
	init_res := gfx.init({})
	testing.expect(t, init_res == nil)
	gfx.fini()

	init_res = gfx.init({})
	testing.expect(t, init_res == nil)
	gfx.fini()
}

