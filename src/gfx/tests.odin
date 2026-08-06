#+private
package gfx

import "core:testing"

@(test)
check_init_fini :: proc(t: ^testing.T) {
	init({})
	fini()
}

@(test)
check_multi_init :: proc(t: ^testing.T) {
	init({})
	fini()

	init({})
	fini()
}

