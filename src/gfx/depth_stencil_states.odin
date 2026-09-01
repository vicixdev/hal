package gfx

import "base:runtime"
import "core:sync"
import hm "core:container/handle_map"

Depth_Stencil_State :: distinct Handle

Compare_Operation :: enum {
	Never,
	Less,
	Equal,
	Less_Equal,
	Greater,
	Not_Equal,
	Greater_Equal,
	Always,
}

Stencil_Operation :: enum {
	Keep,
	Zero,
	Replace,
	Increment_Clamp,
	Decrement_Clamp,
	Invert,
	Increment_Wrap,
	Decrement_Wrap,
}

Stencil_Descriptor :: struct {
	test:		Compare_Operation,
	fail:		Stencil_Operation,
	pass:		Stencil_Operation,
	depth_fail:	Stencil_Operation,
	reference:	u32,
	read_mask:	u32,
	write_mask:	u32,
}

Depth_Stencil_Descriptor :: struct {
	depth_enable:			bool,
	depth_write:			bool,
	depth_test:			Compare_Operation,
	depth_bias:			f32,
	depth_bias_slope_factor:	f32,
	depth_bias_clamp:		f32,

	stencil_enable:			bool,
	stencil_front:			Stencil_Descriptor,
	stencil_back:			Stencil_Descriptor,
}

_Depth_Stencil_State_Metadata :: struct {
	handle:		Depth_Stencil_State,

	using desc:	Depth_Stencil_Descriptor,

	using platform:	struct #raw_union {
		m3:	m3_Depth_Stencil_State_Metadata,
		vk:	vk_Depth_Stencil_State_Metadata,
	},
}

_depth_stencil_states:		hm.Dynamic_Handle_Map(_Depth_Stencil_State_Metadata, Depth_Stencil_State)
_depth_stencil_states_mutex:	sync.RW_Mutex

create_depth_stencil_state :: proc(
	descriptor:	Depth_Stencil_Descriptor,
	location :=	#caller_location,
) -> (depth_stencil_state: Depth_Stencil_State, res: Result) {

	handle, metadata := _add_depth_stencil_state_metadata() or_return

	descriptor := descriptor
	if !descriptor.depth_enable {
		descriptor.depth_write	= false
		descriptor.depth_test	= .Always
	}
	if !descriptor.stencil_enable {
		descriptor.stencil_front.test		= .Always
		descriptor.stencil_front.pass		= .Keep
		descriptor.stencil_front.fail		= .Keep
		descriptor.stencil_front.depth_fail	= .Keep
		descriptor.stencil_front.read_mask	= 0xFFFFFFFF
		descriptor.stencil_front.write_mask	= 0

		descriptor.stencil_back.test		= .Always
		descriptor.stencil_back.pass		= .Keep
		descriptor.stencil_back.fail		= .Keep
		descriptor.stencil_back.depth_fail	= .Keep
		descriptor.stencil_back.read_mask	= 0xFFFFFFFF
		descriptor.stencil_back.write_mask	= 0
	}

	metadata.desc = descriptor

	when TARGET_API == .Vulkan {
		res = vk_create_depth_stencil_state(metadata, descriptor)
	} else when TARGET_API == .Metal_3 {
		res = m3_create_depth_stencil_state(metadata, descriptor)
	}

	_check_generic_backend_error(res, location)

	return handle, nil
}

destroy_depth_stencil_state :: proc(depth_stencil_state: Depth_Stencil_State, location := #caller_location) {
	metadata, metadata_res := _metadata_of(depth_stencil_state)
	_check_depth_stencil_state_handle(metadata_res, depth_stencil_state, location)
	if metadata_res != nil do return

	when TARGET_API == .Vulkan {
		vk_destroy_depth_stencil_state(metadata)
	} else when TARGET_API == .Metal_3 {
		m3_destroy_depth_stencil_state(metadata)
	}

	_remove_depth_stencil_state_metadata(depth_stencil_state)
}

_check_depth_stencil_state_handle :: proc(
	result:		Result,
	depth_stencil_state:	Depth_Stencil_State,
	location:	runtime.Source_Code_Location,
) -> Result {

	_check_result(
		result,
		.Warning,
		"Invalid resource handle",
		"Invalid depth_stencil_state handle (%v).",
		depth_stencil_state,
		location=location,
	) or_return
	return nil
}

_depth_stencil_state_metadata_of :: proc(
	depth_stencil_state: Depth_Stencil_State,
) -> (^_Depth_Stencil_State_Metadata, Result) {

	sync.shared_guard(&_depth_stencil_states_mutex)

	metadata, ok := hm.get(&_depth_stencil_states, depth_stencil_state)
	if !ok {
		return nil, .Invalid_Depth_Stencil_State
	}
	
	return metadata, nil
}

_add_depth_stencil_state_metadata :: proc() -> (
	depth_stencil_state:	Depth_Stencil_State,
	metadata:		^_Depth_Stencil_State_Metadata,
	res:			Result,
) {
	sync.guard(&_depth_stencil_states_mutex)

	depth_stencil_state = hm.add(&_depth_stencil_states, _Depth_Stencil_State_Metadata {}) or_return
	metadata = hm.get(&_depth_stencil_states, depth_stencil_state)

	return
}

_remove_depth_stencil_state_metadata :: proc(depth_stencil_state: Depth_Stencil_State) {
	sync.guard(&_depth_stencil_states_mutex)

	hm.remove(&_depth_stencil_states, depth_stencil_state)
}



