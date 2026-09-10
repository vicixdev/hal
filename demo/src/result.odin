package main

import "base:runtime"
import "core:os"
import "root:gfx"

Error :: enum {
	Invalid_Handle,
	Exists_Already,

	Could_Not_Parse_File,

	Out_Of_Atlas_Space,

	Generic_Error,
}

Result :: union {
	runtime.Allocator_Error,
	os.Error,
	gfx.Result,
	Error,
}

