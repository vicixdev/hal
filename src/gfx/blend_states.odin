package gfx

import "base:runtime"
import "core:sync"
import hm "core:container/handle_map"

Blend_State :: distinct Handle

Blend_Operation :: enum {
	Add,
	Subtract,
	Reverse_Subtract,
	Min,
	Max,
}

Blend_Factor :: enum {
	Zero,
	One,
	Source_Color,
	Destination_Color,
	Source_Alpha,
	Destination_Alpha,
	Constant_Color,
	Constant_Alpha,
	One_Minus_Source_Color,
	One_Minus_Destination_Color,
	One_Minus_Source_Alpha,
	One_Minus_Destination_Alpha,
	One_Minus_Constant_Color,
	One_Minus_Constant_Alpha,
}

Blend_Descriptor :: struct {
	color_op:			Blend_Operation,
	source_color_factor:		Blend_Factor,
	destination_color_factor:	Blend_Factor,
	alpha_op:			Blend_Operation,
	source_alpha_factor:		Blend_Factor,
	destination_alpha_factor:	Blend_Factor,
}

_Blend_State_Metadata :: struct {
	handle:		Blend_State,

	using desc:	Blend_Descriptor,

	using platform:	struct #raw_union {
		m3:	m3_Blend_State_Metadata,
		vk:	vk_Blend_State_Metadata,
	},
}

_blend_states:		hm.Dynamic_Handle_Map(_Blend_State_Metadata, Blend_State)
_blend_states_mutex:	sync.RW_Mutex

create_blend_state :: proc(
	descriptor:	Blend_Descriptor,
	location :=	#caller_location,
) -> (blend_state: Blend_State, res: Result) {

	handle, metadata := _add_blend_state_metadata() or_return

	metadata.desc = descriptor

	when TARGET_API == .Vulkan {
		res = vk_create_blend_state(metadata, descriptor)
	} else when TARGET_API == .Metal_3 {
		res = m3_create_blend_state(metadata, descriptor)
	}

	_check_generic_backend_error(res, location)

	return handle, nil
}

destroy_blend_state :: proc(blend_state: Blend_State, location := #caller_location) {
	metadata, metadata_res := _metadata_of(blend_state)
	_check_blend_state_handle(metadata_res, blend_state, location)
	if metadata_res != nil do return

	when TARGET_API == .Vulkan {
		vk_destroy_blend_state(metadata)
	} else when TARGET_API == .Metal_3 {
		m3_destroy_blend_state(metadata)
	}

	_remove_blend_state_metadata(blend_state)
}

_check_blend_state_handle :: proc(
	result:		Result,
	blend_state:	Blend_State,
	location:	runtime.Source_Code_Location,
) -> Result {

	_check_result(
		result,
		.Warning,
		"Invalid resource handle",
		"Invalid blend_state handle (%v).",
		blend_state,
		location=location,
	) or_return
	return nil
}

_blend_state_metadata_of :: proc(blend_state: Blend_State) -> (^_Blend_State_Metadata, Result) {
	sync.shared_guard(&_blend_states_mutex)

	metadata, ok := hm.get(&_blend_states, blend_state)
	if !ok {
		return nil, .Invalid_Blend_State
	}
	
	return metadata, nil
}

_add_blend_state_metadata :: proc() -> (blend_state: Blend_State, metadata: ^_Blend_State_Metadata, res: Result) {
	sync.guard(&_blend_states_mutex)

	blend_state = hm.add(&_blend_states, _Blend_State_Metadata {}) or_return
	metadata = hm.get(&_blend_states, blend_state)

	return
}

_remove_blend_state_metadata :: proc(blend_state: Blend_State) {
	sync.guard(&_blend_states_mutex)

	hm.remove(&_blend_states, blend_state)
}


