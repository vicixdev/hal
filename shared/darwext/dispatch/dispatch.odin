#+build darwin
package darwext_dispatch

import "base:runtime"
import NS "core:sys/darwin/Foundation"

data_t	:: ^NS.Object
queue_t	:: ^NS.Object
block_t	:: ^NS.Block

DATA_DESTRUCTOR_DEFAULT: block_t

@(link_prefix="dispatch_")
foreign {
	get_main_queue :: proc "c" () -> queue_t ---
	get_global_queue :: proc "c" () -> queue_t ---

	data_create :: proc "c" (buffer: rawptr, size: uintptr, queue: queue_t, block: block_t) -> data_t ---
}

@(init, private)
init_constants :: proc "contextless" () {
	context = runtime.default_context()

	DATA_DESTRUCTOR_DEFAULT = NS.Block_createGlobal(nil, proc "c" (rawptr) {})
}

@(fini)
fini_constants :: proc "contextless" () {
	context = runtime.default_context()

	DATA_DESTRUCTOR_DEFAULT->release()
}

