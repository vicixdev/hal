package vicixdev_gfx

import "base:runtime"
import "core:sync"
import "core:slice"
import vmem "core:mem/virtual"

Command_Buffer :: bit_field u64 {
	queue:		Queue	| 2,
	index:		u32	| 30,
	generation:	u32	| 32,
}

Semaphore_Wait :: struct {
	semaphore:	Semaphore,
	value:		int,
}

Semaphore_Signal :: struct {
	semaphore:	Semaphore,
	value:		int,
}

Render_Pass_Wait :: struct {
	fences:		[]Fence,
	before:		Stages,
}

Render_Pass_Signal :: struct {
	fences:		[]Fence,
	after:		Stages,
}

Index_Type :: enum {
	U16,
	U32,
}

_Command_Buffer_Metadata :: struct {
	handle:					Command_Buffer,

	arena:					vmem.Arena,
	allocator:				runtime.Allocator,

	queue:					Queue,
	in_use:					bool,

	resource_set:				Resource_Set,
	depth_stencil_state:			Depth_Stencil_State,
	blend_constant:				[4]f64,
	semaphore_waits:			[]Semaphore_Wait,
	commands:				[dynamic]_Command,

	can_encode_signals:			bool,
	is_encoding_render_pass:		bool,
	render_pass_attachment_sample_count:	int,

	// TODO: Implement these and validate the bound render pipeline
	render_pass_color_formats:		[]Pixel_Format,
	render_pass_depth_format:		Maybe(Pixel_Format),
	render_pass_stencil_format:		Maybe(Pixel_Format),

	using platform:	struct #raw_union {
		vk:	vk_Command_Buffer_Metadata,
		m3:	m3_Command_Buffer_Metadata,
	},
}

_Command :: union {
	_Command_Mem_Copy,
	_Command_Copy_Texture_To_Texture,
	_Command_Copy_Buffer_To_Texture,
	_Command_Copy_Texture_To_Buffer,
	_Command_Dispatch,
	_Command_Barrier,
	_Command_Signal,
	_Command_Wait,
	_Command_Begin_Render_Pass,
	_Command_End_Render_Pass,
	_Command_Draw,
	_Command_Draw_Indexed,
}

_Command_Mem_Copy :: struct {
	source:		_Address_Info,
	destination:	_Address_Info,
	size:		int,
}

_Command_Copy_Texture_To_Texture :: struct {
	source:			Texture,
	source_region:		Texture_Region,
	destination:		Texture,
	destination_region:	Texture_Region,
}

_Command_Copy_Buffer_To_Texture :: struct {
	source:		_Address_Info,
	texture:	Texture,
	region:		Texture_Region,
}

_Command_Copy_Texture_To_Buffer :: struct {
	texture:	Texture,
	region:		Texture_Region,
	destination:	_Address_Info,
}

_Command_Barrier :: struct {
	after:		Stages,
	before:		Stages,
}

_Command_Dispatch :: struct {
	pipeline:	Pipeline,
	resource_set:	Resource_Set,
	arguments:	_Address_Info,
	group_count:	[3]int,
}

_Command_Signal :: struct {
	signals:	[]Fence,
}

_Command_Wait :: struct {
	waits:		[]Fence,
}

_Command_Signal_Semaphore :: struct {
	semaphore:	Semaphore,
	value:		int,
}

_Command_Begin_Render_Pass :: struct {
	using desc:			Render_Pass_Descriptor,

	signals:			[]Render_Pass_Signal,
	waits:				[]Render_Pass_Wait,

	attachment_dimensions:		[2]int,
	attachment_sample_count:	int,
}

_Command_End_Render_Pass :: struct {}

_Command_Draw :: struct {
	pipeline:		Pipeline,
	resource_set:		Resource_Set,
	depth_stencil_state:	Depth_Stencil_State,
	blend_constant:		[4]f64,
	arguments:		_Address_Info,
	vertex_count:		int,
	instance_count:		int,
	base_vertex:		int,
}

_Command_Draw_Indexed :: struct {
	pipeline:		Pipeline,
	resource_set:		Resource_Set,
	depth_stencil_state:	Depth_Stencil_State,
	blend_constant:		[4]f64,
	arguments:		_Address_Info,
	indices:		_Address_Info,
	index_count:		int,
	instance_count:		int,
	base_vertex:		int,
	index_type:		Index_Type,
}

_Semaphore_Wait :: struct {
	semaphore:	^_Semaphore_Metadata,
	value:		int,
}

_command_buffers:	[Queue][16]_Command_Buffer_Metadata
_command_buffers_mutex:	sync.RW_Mutex

_setup_command_buffers_of :: proc(queue: Queue) -> Result {
	queue_metadata := &_queues[queue]

	for &metadata, i in _command_buffers[queue] {
		_setup_command_buffer(&metadata, queue_metadata, i) or_return
	}

	return nil
}

_destroy_command_buffers_of :: proc(queue: Queue) {
	queue_metadata := &_queues[queue]

	for &metadata in _command_buffers[queue] {
		_destroy_command_buffer(&metadata, queue_metadata)
	}
}

_setup_command_buffer :: proc(
	metadata: ^_Command_Buffer_Metadata,
	queue_metadata: ^_Queue_Metadata,
	index: int,
) -> Result {
	metadata.handle.queue = queue_metadata.type
	metadata.handle.index = cast(u32)index

	metadata.queue = queue_metadata.type

	vmem.arena_init_growing(&metadata.arena) or_return
	metadata.allocator = vmem.arena_allocator(&metadata.arena)

	metadata.commands = make([dynamic]_Command, metadata.allocator) or_return

	when TARGET_API == .Vulkan {
		vk_setup_command_buffer(metadata, queue_metadata) or_return
	} else when TARGET_API == .Metal_3 {
		m3_setup_command_buffer(metadata, queue_metadata) or_return
	}

	return nil
}

_destroy_command_buffer :: proc(
	metadata:	^_Command_Buffer_Metadata,
	queue_metadata:	^_Queue_Metadata,
) {
	
	vmem.arena_destroy(&metadata.arena)

	when TARGET_API == .Vulkan {
		vk_destroy_command_buffer(metadata, queue_metadata)
	} else when TARGET_API == .Metal_3 {
		m3_destroy_command_buffer(metadata, queue_metadata)
	}
}

begin_command_encoding :: proc(
	queue:		Queue,
	waits:		..Semaphore_Wait,
	location	:= #caller_location,
) -> (command_buffer: Command_Buffer, res: Result) {

	_check_queue_validity(queue, location)
	
	for wait in waits {
		_, semaphore_res := _metadata_of(wait.semaphore)
		_check_semaphore_handle(semaphore_res, wait.semaphore, location) or_return
	}

	handle, metadata, add_res := _add_command_buffer(queue)
	_check_result(
		add_res,
		.Error,
		"Queue already in use",
		"The queue `%v` is already in use by another command buffer. Please submit it before start encoding " +
		"another one.",
		queue,
		location=location,
	) or_return

	vmem.arena_free_all(&metadata.arena)

	metadata.resource_set		= _default_resource_set
	metadata.depth_stencil_state	= _default_depth_stencil_state
	metadata.blend_constant		= 0
	metadata.can_encode_signals	= false
	metadata.is_encoding_render_pass = false
	metadata.commands = make([dynamic]_Command, metadata.allocator) or_return

	if len(waits) > 0 {
		metadata.semaphore_waits = slice.clone(waits, metadata.allocator) or_return
	} else {
		metadata.semaphore_waits = {}
	}

	return handle, nil
}

use_resources :: proc(
	command_buffer:	Command_Buffer,
	resource_set:	Resource_Set,
	location :=	#caller_location,
) -> (res: Result) {
	
	metadata, metadata_res := _metadata_of(command_buffer)
	_check_command_buffer_handle(metadata_res, command_buffer, location) or_return

	_, resource_set_res := _metadata_of(resource_set)
	_check_resource_set_handle(resource_set_res, resource_set, location) or_return
	
	metadata.resource_set = resource_set

	return nil
}

use_depth_stencil_state :: proc(
	command_buffer:		Command_Buffer,
	depth_stencil_state:	Depth_Stencil_State,
	location :=		#caller_location,
) -> (res: Result) {
	
	metadata, metadata_res := _metadata_of(command_buffer)
	_check_command_buffer_handle(metadata_res, command_buffer, location) or_return

	_, depth_stencil_res := _metadata_of(depth_stencil_state)
	_check_depth_stencil_state_handle(depth_stencil_res, depth_stencil_state, location) or_return
	
	metadata.depth_stencil_state = depth_stencil_state

	return nil
}

use_blend_constant :: proc(
	command_buffer:		Command_Buffer,
	blend_constant:		[4]f64,
	location :=		#caller_location,
) -> (res: Result) {

	metadata, metadata_res := _metadata_of(command_buffer)
	_check_command_buffer_handle(metadata_res, command_buffer, location) or_return

	metadata.blend_constant = blend_constant

	return nil
}

mem_copy :: proc(
	command_buffer:	Command_Buffer,
	destination:	rawptr,
	source:		rawptr,
	size:		int,
	location :=	#caller_location,
) -> (res: Result) {

	metadata, metadata_res := _metadata_of(command_buffer)
	_check_command_buffer_handle(metadata_res, command_buffer, location) or_return

	_check_not_in_render_pass(metadata, location) or_return

	destination_info, destination_res := _address_info_of(destination)
	_check_address_info(destination_res, destination, location) or_return

	destination_metadata, destination_metadata_res := _metadata_of(destination_info.buffer)
	assert(destination_metadata_res == nil)

	source_info, source_res := _address_info_of(source)
	_check_address_info(source_res, source, location) or_return

	source_metadata, source_metadata_res := _metadata_of(source_info.buffer)
	assert(source_metadata_res == nil)

	_check_condition(
		destination_info.remaining_size >= cast(uintptr)size,
		.Out_Of_Bounds,
		.Error,
		"Out of bounds copy",
		"The requested memory copy operation would result in out of bounds accesses. The user specified a " +
		"copy lenth of %d, but the destination buffer (at 0x%x) has only %d bytes remaining at offset %d.",
		size,
		destination,
		destination_info.remaining_size,
		destination_info.offset,
		location=location,
	) or_return
	_check_condition(
		source_info.remaining_size >= cast(uintptr)size,
		.Out_Of_Bounds,
		.Error,
		"Out of bounds copy",
		"The requested memory copy operation would result in out of bounds accesses. The user specified a " +
		"copy lenth of %d, but the source buffer (at 0x%x) has only %d bytes remaining at offset %d.",
		size,
		source,
		source_info.remaining_size,
		source_info.offset,
		location=location,
	) or_return

	_check_condition(
		source_metadata.memory_type != .Readback,
		.Incompatible_Memory_Type,
		.Error,
		"Incorrect source memory type",
		"The source buffer (at 0x%x) is of memory type `.Readback`. `.Readback` buffers can only be used as " +
		"destination. To upload data consider using `.Default` buffers for small memory sizes or `.Staging` " +
		"for bigger ones.",
		source,
		location=location,
	) or_return
	_check_condition(
		destination_metadata.memory_type != .Staging,
		.Incompatible_Memory_Type,
		.Error,
		"Incorrect destination memory type",
		"The destination buffer (at 0x%x) is of memory type `.Staging`. `.Staging` buffers can only be used " +
		"as source. To download data consider using `.Default` buffers for small memory sizes or `.Readback` " +
		"for bigger ones.",
		destination,
		location=location,
	) or_return

	command := _Command_Mem_Copy {
		source		= source_info,
		destination	= destination_info,
		size		= size,
	}
	append(&metadata.commands, command)

	metadata.can_encode_signals = true

	return nil
}

copy_texture_to_texture :: proc(
	command_buffer:		Command_Buffer,
	source:			Texture,
	source_region:		Texture_Region,
	destination:		Texture,
	destination_region:	Texture_Region,
	location :=		#caller_location,
) -> Result {

	metadata, metadata_res := _metadata_of(command_buffer)
	_check_command_buffer_handle(metadata_res, command_buffer, location) or_return
	
	_check_not_in_render_pass(metadata, location) or_return

	source_metadata, source_res := _metadata_of(source)
	_check_texture_handle(source_res, source, location) or_return

	destination_metadata, destination_res := _metadata_of(destination)
	_check_texture_handle(destination_res, destination, location) or_return

	_check_texture_region(source_metadata, source_region, location) or_return
	_check_texture_region(destination_metadata, destination_region, location) or_return

	_check_condition(
		source_region.size == destination_region.size,
		.Invalid_Arguments,
		.Error,
		"Invalid copy sizes",
		"The source and destination copy size must be the same. Got %v and %v.",
		source_region.size,
		destination_region.size,
		location=location,
	) or_return
	_check_condition(
		source_region.layer_count == destination_region.layer_count,
		.Invalid_Arguments,
		.Error,
		"Invalid copy layer counts",
		"The source and destination copy layer count must be the same. Got %v and %v.",
		source_region.layer_count,
		destination_region.layer_count,
		location=location,
	) or_return

	_check_condition(
		_COPY_TEXTURE_TO_TEXTURE_COMPATIBILITIES[source_metadata.format][source_metadata.format],
		.Invalid_Arguments,
		.Error,
		"Incompatible texture formats",
		"The formats %v (source) and %v (destination) are incompatible.",
		source_metadata.format,
		destination_metadata.format,
		location=location,
	) or_return

	command := _Command_Copy_Texture_To_Texture {
		source			= source,
		source_region		= source_region,
		destination		= destination,
		destination_region	= destination_region,
	}
	append(&metadata.commands, command) or_return

	metadata.can_encode_signals = true

	return nil
}

copy_buffer_to_texture :: proc(
	command_buffer:	Command_Buffer,
	source:		rawptr,
	texture:	Texture,
	region:		Texture_Region,
	location :=	#caller_location,
) -> Result {
	metadata, metadata_res := _metadata_of(command_buffer)
	_check_command_buffer_handle(metadata_res, command_buffer, location) or_return
	
	_check_not_in_render_pass(metadata, location) or_return

	texture_metadata, texture_res := _metadata_of(texture)
	_check_texture_handle(texture_res, texture, location) or_return

	source_info, source_res := _address_info_of(source)
	_check_address_info(source_res, source, location) or_return

	source_metadata, source_metadata_res := _metadata_of(source_info.buffer)
	assert(source_metadata_res == nil)
	source_offset := source_info.offset

	required_size := _size_of_texture_region(texture_metadata, region)

	_check_condition(
		source_metadata.memory_type != .Readback,
		.Incompatible_Memory_Type,
		.Error,
		"Incorrect source memory type",
		"The source buffer (at 0x%x) is of memory type `.Readback`. `.Readback` buffers can only be used as " +
		"destination. To upload data consider using `.Default` buffers for small memory sizes or `.Staging` " +
		"for bigger ones.",
		source,
		location=location,
	) or_return
	_check_condition(
		source_info.remaining_size >= cast(uintptr)required_size,
		.Out_Of_Bounds,
		.Error,
		"Out of bounds copy",
		"The requested memory copy operation would result in out of bounds accesses. The texture copy wopuld " +
		"require a length of %d, but the source buffer (at 0x%x) has only %d bytes remaining at offset " +
		"%d.",
		required_size,
		source,
		source_info.remaining_size,
		source_offset,
		location=location,
	) or_return

	command := _Command_Copy_Buffer_To_Texture {
		source		= source_info,
		texture		= texture,
		region		= region,
	}
	append(&metadata.commands, command) or_return

	return nil
}

copy_texture_to_buffer :: proc(
	command_buffer:	Command_Buffer,
	texture:	Texture,
	region:		Texture_Region,
	destination:	rawptr,
	location :=	#caller_location,
) -> Result {
	metadata, metadata_res := _metadata_of(command_buffer)
	_check_command_buffer_handle(metadata_res, command_buffer, location) or_return
	
	_check_not_in_render_pass(metadata, location) or_return

	texture_metadata, texture_res := _metadata_of(texture)
	_check_texture_handle(texture_res, texture, location) or_return

	destination_info, destination_res := _address_info_of(destination)
	_check_address_info(destination_res, destination, location) or_return

	destination_metadata, destination_metadata_res := _metadata_of(destination_info.buffer)
	assert(destination_metadata_res == nil)
	destination_offset := destination_info.offset

	required_size := _size_of_texture_region(texture_metadata, region)

	_check_condition(
		destination_metadata.memory_type != .Staging,
		.Incompatible_Memory_Type,
		.Error,
		"Incorrect destination memory type",
		"The destination buffer (at 0x%x) is of memory type `.Staging`. `.Staging` buffers can only be used " +
		"as source. To download data consider using `.Default` buffers for small memory sizes or `.Readback` " +
		"for bigger ones.",
		destination,
		location=location,
	) or_return
	_check_condition(
		destination_info.remaining_size >= cast(uintptr)required_size,
		.Out_Of_Bounds,
		.Error,
		"Out of bounds copy",
		"The requested memory copy operation would result in out of bounds accesses. The texture copy wopuld " +
		"require a length of %d, but the destination buffer (at 0x%x) has only %d bytes remaining at offset " +
		"%d.",
		required_size,
		destination,
		destination_info.remaining_size,
		destination_offset,
		location=location,
	) or_return

	command := _Command_Copy_Texture_To_Buffer {
		texture		= texture,
		region		= region,
		destination	= destination_info,
	}
	append(&metadata.commands, command) or_return

	return nil
}

dispatch :: proc(
	command_buffer:		Command_Buffer,
	compute_pipeline:	Pipeline,
	arguments:		rawptr,
	group_count:		[3]int,
	location :=		#caller_location,
) -> (res: Result) {
	
	metadata, metadata_res := _metadata_of(command_buffer)
	_check_command_buffer_handle(metadata_res, command_buffer, location) or_return

	_check_not_in_render_pass(metadata, location) or_return

	pipeline_metadata, pipeline_res := _metadata_of(compute_pipeline)
	_check_pipeline_handle(pipeline_res, compute_pipeline, location) or_return

	_check_condition(
		pipeline_metadata.type == .Compute,
		.Invalid_Pipeline,
		.Error,
		"Invalid pipeline type",
		"A dispatch requires a compute pipeline. The provided pipeline %v is of type %v.",
		compute_pipeline,
		pipeline_metadata.type,
		location=location,
	)

	arguments_info, arguments_res := _address_info_of(arguments)
	_check_address_info(arguments_res, arguments, location) or_return

	command :=  _Command_Dispatch {
		pipeline	= compute_pipeline,
		resource_set	= metadata.resource_set,
		arguments	= arguments_info,
		group_count	= group_count,
	}
	append(&metadata.commands, command) or_return

	metadata.can_encode_signals = true

	return nil
}

// Emplaces a synchronization barrier in the command buffer.
//
// A memory dependency is emplaced between `after` (producing) and `before` (consuming).
barrier	:: proc(
	command_buffer: Command_Buffer,
	after:		Stages,
	before:		Stages,
	location := #caller_location,
) -> Result {
	metadata, metadata_res := _metadata_of(command_buffer)
	_check_command_buffer_handle(metadata_res, command_buffer, location) or_return

	_check_not_in_render_pass(metadata, location) or_return

	_check_condition(
		after != {} && before != {},
		.Invalid_Arguments,
		.Error,
		"Invalid `before` and `after` stages",
		"Both `after` and `before` stages must not be empty ({}).",
		location=location,
	) or_return

	command := _Command_Barrier {
		after	= after,
		before	= before,
	}
	append(&metadata.commands, command) or_return

	metadata.can_encode_signals = false

	return nil
}

signal :: proc(command_buffer: Command_Buffer, fences: ..Fence, location := #caller_location) -> Result {
	metadata, metadata_res := _metadata_of(command_buffer)
	_check_command_buffer_handle(metadata_res, command_buffer, location) or_return

	_check_not_in_render_pass(metadata, location) or_return

	_check_condition(
		metadata.can_encode_signals,
		.Invalid_Arguments,
		.Error,
		"Invalid signal operation",
		"A signal operation can be issued only after other commands have been encoded in the command buffer " +
		"after the last signal, wait and barrier. A signal to fences %v on command buffer %v has been issued " +
		"while no commands are present after the last signal, wait or barrier.",
		fences,
		command_buffer,
		location=location,
	) or_return

	for fence in fences {
		_, fence_res := _metadata_of(fence)
		_check_fence_handle(fence_res, fence, location) or_return
	}

	command := _Command_Signal {
		signals = slice.clone(fences, metadata.allocator) or_return,
	}
	append(&metadata.commands, command) or_return

	metadata.can_encode_signals = false

	return nil
}

wait :: proc(command_buffer: Command_Buffer, fences: ..Fence, location := #caller_location) -> Result {
	metadata, metadata_res := _metadata_of(command_buffer)
	_check_command_buffer_handle(metadata_res, command_buffer, location) or_return

	_check_not_in_render_pass(metadata, location) or_return

	for fence in fences {
		_, fence_res := _metadata_of(fence)
		_check_fence_handle(fence_res, fence, location) or_return
	}

	command := _Command_Wait {
		waits = slice.clone(fences, metadata.allocator) or_return,
	}
	append(&metadata.commands, command) or_return

	metadata.can_encode_signals = false

	return nil
}

begin_render_pass :: proc(
	command_buffer:	Command_Buffer,
	descriptor:	Render_Pass_Descriptor,
	signals:	[]Render_Pass_Signal	= {},
	waits:		[]Render_Pass_Wait	= {},
	location :=	#caller_location,
) -> Result {

	check_attachment_dimensions_and_sample_count :: proc(
		reference_dimensions:	^[3]int,
		reference_samples:	^int,
		view:			View,
		dimensions:		[3]int,
		samples:		int,
		location:		runtime.Source_Code_Location,
	) -> Result {

		if reference_dimensions^ == {} {
			reference_dimensions^ = dimensions
		} else {
			_check_condition(
				reference_dimensions^ == dimensions,
				.Invalid_Arguments,
				.Error,
				"Invalid attachment dimensions",
				"The dimensions of the provided attachment %v (%v) do not conform with the " +
				"dimensions of the previous attachments (%v).",
				view,
				dimensions,
				reference_dimensions,
				location=location,
			) or_return
		}

		if reference_samples^ == 0 {
			reference_samples^ = samples
		} else {
			_check_condition(
				reference_samples^ == samples,
				.Invalid_Arguments,
				.Error,
				"Invalid attachment samples",
				"The sample count of the provided attachment %v (%v) does not conform with the " +
				"sample count of the previous attachments (%v).",
				view,
				samples,
				reference_samples^,
				location=location,
			) or_return
		}

		return nil
	}

	metadata, metadata_res := _metadata_of(command_buffer)
	_check_command_buffer_handle(metadata_res, command_buffer, location) or_return

	attachment_dimensions:	[3]int
	attachment_samples:	int

	for color_target in descriptor.color_attachments {
		view_metadata, view_res := _metadata_of(color_target.view)
		_check_view_handle(view_res, color_target.view, location) or_return

		_check_condition(
			view_metadata.type == .D2,
			.Invalid_Arguments,
			.Error,
			"Invalid view",
			"Only views of type `.D2` can be used as renderpass attachments. View %v is of type %v.",
			color_target.view,
			view_metadata.type,
			location=location,
		) or_return

		view_dimensions:	[3]int
		view_sample_count:	int
		view_format:		Pixel_Format

		switch v in view_metadata.reference {
		case Texture:
			texture_metadata, texture_res := _metadata_of(v)
			_check_texture_handle(texture_res, v, location) or_return
		
			_check_condition(
				.Color_Attachment in texture_metadata.usage,
				.Invalid_Arguments,
				.Error,
				"Invalid texture",
				"A texture, in order to be used as a color render target must be created with the " +
				"`.Color_Attachment` usage. Texture %v (referenced by view %v) has usage %v.",
				v,
				color_target.view,
				location=location,
			) or_return

			_, has_clear_color := color_target.clear_value.([4]f64)
			_check_condition(
				has_clear_color,
				.Invalid_Arguments,
				.Error,
				"Invalid color clear value",
				"A color render target can only be cleared with a `[4]f64` value. `u32` is reverved " +
				"for stencil attachments and `f64` is reserved for depth attachments. Found clear " +
				"value `%v`.",
				color_target.clear_value,
				location=location,
			) or_return

			view_dimensions		= texture_metadata.dimensions
			view_sample_count	= texture_metadata.sample_count
			view_format		= texture_metadata.format

		case Surface:
			surface_metadata, surface_res := _metadata_of(v)
			_check_surface_handle(surface_res, v, location) or_return

			was_used := sync.atomic_exchange(&view_metadata.used, true)
			_check_condition(
				!was_used,
				.Invalid_View,
				.Error,
				"Invalid view",
				"A view referencing a surface can only be used once as a color attachment in a " +
				"render pass. View %s has been used multiple times.",
				color_target.view,
				location=location,
			) or_return

			view_dimensions		= { **surface_metadata.dimensions, 1 }
			view_sample_count	= 1
			view_format		= surface_metadata.format
		}

		check_attachment_dimensions_and_sample_count(
			&attachment_dimensions,
			&attachment_samples,
			color_target.view,
			view_dimensions,
			view_sample_count,
			location=location,
		) or_return
		assert(
			_HAS_PIXEL_FORMAT_COLOR[view_format],
			"The texture pixel format does not have color information. This should have been checked " +
			"during the texture creation.",
		)

		_check_condition(
			_impl(color_target.resolve_view != {}, attachment_samples > 1),
			.Invalid_View,
			.Error,
			"Invalid resolve view",
			"The resolve view can only be used if the sample count of the attachments is more than 1. " +
			"The resolve view %v has been provided when the previous attachments are using 1 samples.",
			color_target.resolve_view,
			location=location,
		) or_return

		if color_target.resolve_view != {} {
			resolve_view_metadata, resolve_view_res := _metadata_of(color_target.resolve_view)
			_check_view_handle(resolve_view_res, color_target.resolve_view, location) or_return

			resolve_view_dimensions:	[3]int
			resolve_view_sample_count:	int
			resolve_view_format:		Pixel_Format

			switch v in resolve_view_metadata.reference {
			case Texture:
				texture_metadata, texture_res := _metadata_of(v)
				assert(texture_res == nil)

				resolve_view_dimensions		= texture_metadata.dimensions
				resolve_view_sample_count	= texture_metadata.sample_count
				resolve_view_format		= texture_metadata.format

			case Surface:
				surface_metadata, surface_res := _metadata_of(v)
				assert(surface_res == nil)

				was_used := sync.atomic_exchange(&resolve_view_metadata.used, true)
				_check_condition(
					!was_used,
					.Invalid_View,
					.Error,
					"Invalid view",
					"A view referencing a surface can only be used once as a color attachment in a " +
					"render pass. View %s has been used multiple times.",
					color_target.view,
					location=location,
				) or_return

				resolve_view_dimensions		= { **surface_metadata.dimensions, 1 }
				resolve_view_sample_count	= 1
				resolve_view_format		= surface_metadata.format
			}

			_check_condition(
				attachment_dimensions == resolve_view_dimensions,
				.Invalid_Arguments,
				.Error,
				"Invalid attachment dimensions",
				"The dimensions of the provided resolve attachment %v (%v) do not conform with the " +
				"dimensions of the previous attachments (%v).",
				color_target.resolve_view,
				resolve_view_dimensions,
				attachment_dimensions,
				location=location,
			) or_return
			_check_condition(
				resolve_view_sample_count == 1,
				.Invalid_Arguments,
				.Error,
				"Invalid sample count",
				"The sample count of a resolve attachment must be 1. The provided view %v uses %d " +
				"samples.",
				color_target.resolve_view,
				resolve_view_dimensions,
				location=location,
			) or_return
			assert(
				_HAS_PIXEL_FORMAT_COLOR[view_format],
				"The texture pixel format does not have color information. This should have been " +
				"checked during the texture creation.",
			)
		}
	}

	if depth_target, has_depth_target := descriptor.depth_attachment.?; has_depth_target {
		view_metadata, view_res := _metadata_of(depth_target.view)
		_check_view_handle(view_res, depth_target.view, location) or_return

		_check_condition(
			view_metadata.type == .D2,
			.Invalid_Arguments,
			.Error,
			"Invalid view",
			"Only views of type `.D2` can be used as renderpass attachments. View %v is of type %v.",
			depth_target.view,
			view_metadata.type,
			location=location,
		) or_return

		reference, is_referencing_texture := view_metadata.reference.(Texture)
		_check_condition(
			is_referencing_texture,
			.Invalid_View,
			.Error,
			"Invalid view",
			"Views referencing surfaces can only be used as color attachments. Texture view %v " +
			"referencing surface %v is being used as a depth attachment.",
			depth_target.view,
			view_metadata.reference,
			location=location,
		) or_return

		texture_metadata, texture_res := _metadata_of(reference)
		_check_texture_handle(texture_res, reference, location) or_return
		
		_check_condition(
			.Depth_Stencil_Attachment in texture_metadata.usage,
			.Invalid_Arguments,
			.Error,
			"Invalid texture",
			"A texture, in order to be used as a depth render target must be created with the " +
			"`.Depth_Stencil_Attachment` usage. Texture %v (referenced by view %v) has usage %v.",
			reference,
			depth_target.view,
			location=location,
		) or_return

		_, has_clear_depth := depth_target.clear_value.(f64)
		_check_condition(
			has_clear_depth,
			.Invalid_Arguments,
			.Error,
			"Invalid depth clear value",
			"A depth render target can only be cleared with a `f64` value. `u32` is reverved for " +
			"stencil attachments and `[4]f64` is reserved for color attachments. Found clear value `%v`.",
			depth_target.clear_value,
			location=location,
		) or_return

		check_attachment_dimensions_and_sample_count(
			&attachment_dimensions,
			&attachment_samples,
			depth_target.view,
			texture_metadata.dimensions,
			texture_metadata.sample_count,
			location=location,
		) or_return
		_check_condition(
			_HAS_PIXEL_FORMAT_DEPTH[texture_metadata.format],
			.Invalid_Arguments,
			.Error,
			"Invalid depth view",
			"The depth attachment must reference a texture with depth information. The provided depth " +
			"attachment (view %v) references a texture of pixel format %v, which does not contain depth " +
			"information.",
			depth_target.view,
			texture_metadata.format,
			location=location,
		) or_return

		_check_condition(
			depth_target.resolve_view == {},
			.Invalid_View,
			.Error,
			"Invalid resolve view",
			"The depth attachment cannot specify a resolve attachment. View %v was specified.",
			depth_target.resolve_view,
			location=location,
		) or_return

	}

	if stencil_target, has_stencil_target := descriptor.stencil_attachment.?; has_stencil_target {
		view_metadata, view_res := _metadata_of(stencil_target.view)
		_check_view_handle(view_res, stencil_target.view, location) or_return

		_check_condition(
			view_metadata.type == .D2,
			.Invalid_Arguments,
			.Error,
			"Invalid view",
			"Only views of type `.D2` can be used as renderpass attachments. View %v is of type %v.",
			stencil_target.view,
			view_metadata.type,
			location=location,
		) or_return

		reference, is_referencing_texture := view_metadata.reference.(Texture)
		_check_condition(
			is_referencing_texture,
			.Invalid_View,
			.Error,
			"Invalid view",
			"Views referencing surfaces can only be used as color attachments. Texture view %v " +
			"referencing surface %v is being used as a stencil attachment.",
			stencil_target.view,
			view_metadata.reference,
			location=location,
		) or_return

		texture_metadata, texture_res := _metadata_of(reference)
		_check_texture_handle(texture_res, reference, location) or_return
		
		_check_condition(
			.Depth_Stencil_Attachment in texture_metadata.usage,
			.Invalid_Arguments,
			.Error,
			"Invalid texture",
			"A texture, in order to be used as a stencil render target must be created with the " +
			"`.Depth_Stencil_Attachment` usage. Texture %v (referenced by view %v) has usage %v.",
			reference,
			stencil_target.view,
			location=location,
		) or_return

		_, has_clear_stencil := stencil_target.clear_value.(u32)
		_check_condition(
			has_clear_stencil,
			.Invalid_Arguments,
			.Error,
			"Invalid stencil clear stencil",
			"A stencil render target can only be cleared with a `u32` value. `f64` is reverved for " +
			"depth attachments and `[4]f64` is reserved for color attachments. Found clear value `%v`.",
			stencil_target.clear_value,
			location=location,
		) or_return

		check_attachment_dimensions_and_sample_count(
			&attachment_dimensions,
			&attachment_samples,
			stencil_target.view,
			texture_metadata.dimensions,
			texture_metadata.sample_count,
			location=location,
		) or_return
		_check_condition(
			_HAS_PIXEL_FORMAT_STENCIL[texture_metadata.format],
			.Invalid_Arguments,
			.Error,
			"Invalid stencil view",
			"The stencil attachment must reference a texture with stencil information. The provided stencil " +
			"attachment (view %v) references a texture of pixel format %v, which does not contain stencil " +
			"information.",
			stencil_target.view,
			texture_metadata.format,
			location=location,
		) or_return

		_check_condition(
			stencil_target.resolve_view == {},
			.Invalid_View,
			.Error,
			"Invalid resolve view",
			"The stencil attachment cannot specify a resolve attachment. View %v was specified.",
			stencil_target.resolve_view,
			location=location,
		) or_return
	}

	command := _Command_Begin_Render_Pass {
		depth_attachment	= descriptor.depth_attachment,
		stencil_attachment	= descriptor.stencil_attachment,
		color_attachments	= slice.clone(descriptor.color_attachments, metadata.allocator) or_return,
		signals			= slice.clone(signals, metadata.allocator) or_return,
		waits			= slice.clone(waits, metadata.allocator) or_return,
		attachment_dimensions	= attachment_dimensions.xy,
		attachment_sample_count	= attachment_samples,
	}
	append(&metadata.commands, command) or_return

	metadata.can_encode_signals			= false
	metadata.is_encoding_render_pass		= true
	metadata.render_pass_attachment_sample_count	= attachment_samples

	return nil
}

end_render_pass :: proc(command_buffer:	Command_Buffer, location := #caller_location) -> Result {

	metadata, metadata_res := _metadata_of(command_buffer)
	_check_command_buffer_handle(metadata_res, command_buffer, location) or_return

	command := _Command_End_Render_Pass {}
	append(&metadata.commands, command) or_return

	metadata.is_encoding_render_pass = false

	return nil
}

draw :: proc(
	command_buffer:		Command_Buffer,
	render_pipeline:	Pipeline,
	arguments:		rawptr,
	vertex_count:		int,
	instance_count :=	1,
	base_vertex :=		0,
	location :=		#caller_location,
) -> (res: Result) {
	
	metadata, metadata_res := _metadata_of(command_buffer)
	_check_command_buffer_handle(metadata_res, command_buffer, location) or_return

	_check_in_render_pass(metadata, location) or_return

	pipeline_metadata, pipeline_res := _metadata_of(render_pipeline)
	_check_pipeline_handle(pipeline_res, render_pipeline, location) or_return

	_check_condition(
		pipeline_metadata.type == .Render,
		.Invalid_Pipeline,
		.Error,
		"Invalid pipeline type",
		"A draw requires a render pipeline. The provided pipeline %v is of type %v.",
		render_pipeline,
		pipeline_metadata.type,
		location=location,
	) or_return
	_check_condition(
		pipeline_metadata.render.sample_count == metadata.render_pass_attachment_sample_count,
		.Invalid_Pipeline,
		.Error,
		"Invalid pipeline sample count",
		"The specified pipeline %v renders with %d samples, while the render pass is using attachments with " +
		"%d samples.",
		render_pipeline,
		pipeline_metadata.render.sample_count,
		metadata.render_pass_attachment_sample_count,
		location=location,
	) or_return
	
	arguments_info, arguments_res := _address_info_of(arguments)
	_check_address_info(arguments_res, arguments, location) or_return

	command :=  _Command_Draw {
		pipeline		= render_pipeline,
		resource_set		= metadata.resource_set,
		depth_stencil_state	= metadata.depth_stencil_state,
		blend_constant		= metadata.blend_constant,
		arguments		= arguments_info,
		vertex_count		= vertex_count,
		instance_count		= instance_count,
		base_vertex		= base_vertex,
	}
	append(&metadata.commands, command) or_return

	return nil
}

draw_indexed :: proc(
	command_buffer:		Command_Buffer,
	render_pipeline:	Pipeline,
	arguments:		rawptr,
	indices:		rawptr,
	index_count:		int,
	instance_count :=	1,
	index_type :=		Index_Type.U16,
	location :=		#caller_location,
) -> (res: Result) {
	
	metadata, metadata_res := _metadata_of(command_buffer)
	_check_command_buffer_handle(metadata_res, command_buffer, location) or_return

	_check_in_render_pass(metadata, location) or_return

	pipeline_metadata, pipeline_res := _metadata_of(render_pipeline)
	_check_pipeline_handle(pipeline_res, render_pipeline, location) or_return

	arguments_info, arguments_res := _address_info_of(arguments)
	_check_address_info(arguments_res, arguments, location) or_return

	indices_info, indices_res := _address_info_of(indices)
	_check_address_info(indices_res, indices, location) or_return

	_check_condition(
		pipeline_metadata.type == .Render,
		.Invalid_Pipeline,
		.Error,
		"Invalid pipeline type",
		"A draw_indexed requires a render pipeline. The provided pipeline %v is of type %v.",
		render_pipeline,
		pipeline_metadata.type,
		location=location,
	) or_return
	_check_condition(
		pipeline_metadata.render.sample_count == metadata.render_pass_attachment_sample_count,
		.Invalid_Pipeline,
		.Error,
		"Invalid pipeline sample count",
		"The specified pipeline %v renders with %d samples, while the render pass is using attachments with " +
		"%d samples.",
		render_pipeline,
		pipeline_metadata.render.sample_count,
		metadata.render_pass_attachment_sample_count,
		location=location,
	) or_return

	command :=  _Command_Draw_Indexed {
		pipeline		= render_pipeline,
		resource_set		= metadata.resource_set,
		depth_stencil_state	= metadata.depth_stencil_state,
		blend_constant		= metadata.blend_constant,
		arguments		= arguments_info,
		indices			= indices_info,
		index_count		= index_count,
		instance_count		= instance_count,
		index_type		= index_type,
	}
	append(&metadata.commands, command) or_return

	return nil
}

submit :: proc(
	queue:			Queue,
	command_buffers:	[]Command_Buffer,
	signals:		..Semaphore_Signal,
	location :=		#caller_location,
) -> (res: Result) {
	
	_check_queue_validity(queue) or_return
	queue_metadata, _ := _metadata_of(queue)

	for command_buffer in command_buffers {
		command_buffer_metadata, command_buffer_res := _metadata_of(command_buffer)
		_check_command_buffer_handle(command_buffer_res, command_buffer, location) or_return

		_check_condition(
			command_buffer_metadata.queue == queue,
			.Invalid_Command_Buffer,
			.Error,
			"Invalid command buffer",
			"The command buffer %v is not related to the queue %v. It is related to the queue %v.",
			command_buffer,
			queue,
			command_buffer_metadata.queue,
		) or_return

		_check_condition(
			!command_buffer_metadata.is_encoding_render_pass,
			.Invalid_Command_Buffer,
			.Error,
			"Open render pass",
			"Cannot submit the command buffer %v to queue %v, since it has an open render pass. Please " +
			"call `gfx::end_render_pass` before submitting the buffer.",
			command_buffer,
			queue,
			location=location,
		) or_return
	}

	for signal in signals {
		_, semaphore_res := _metadata_of(signal.semaphore)
		_check_semaphore_handle(semaphore_res, signal.semaphore, location) or_return
	}

	_check_fence_correctness(command_buffers, location) or_return

	if sync.guard(&queue_metadata.emission_mutex) {
		when TARGET_API == .Vulkan {
			res = vk_submit(queue_metadata, command_buffers, signals)
		} else {
			res = m3_submit(queue_metadata, command_buffers, signals)
		}
	}

	_check_generic_backend_error(res, location)
	
	for command_buffer in command_buffers {
		_remove_command_buffer(command_buffer)
	}

	return res
}

_check_fence_correctness :: proc(command_buffers: []Command_Buffer, location: runtime.Source_Code_Location) -> Result {

	signaled_fences := make(map[Fence]bool, _temp_allocator)
	for command_buffer in command_buffers {
		metadata, metadata_res := _metadata_of(command_buffer)
		_check_command_buffer_handle(metadata_res, command_buffer, location) or_return

		for command in metadata.commands {
			#partial switch v in command {
			case _Command_Signal:
				for fence in v.signals {
					_, is_present := signaled_fences[fence]
					_check_condition(
						!is_present,
						.Invalid_Argument,
						.Error,
						"Invalid fence signaling",
						"In each submission, a fence can only be signaled once. Fence %v in " +
						"command buffer %v was waited on before its " +
						"signaling operation.",
						command_buffer,
						fence,
						location=location,
					) or_return

					signaled_fences[fence] = false
				}

			case _Command_Wait:
				for fence in v.waits {
					_, is_present := signaled_fences[fence]
					_check_condition(
						is_present,
						.Invalid_Argument,
						.Error,
						"Invalid command submission order",
						"In each submission, the command buffer signaling fences must be submitted " +
						"before the one consuming them. Please note that different command buffers " +
						"working on the same set of fences must be submitted in the same call to " +
						"`gfx::submit`. Fence %v in command buffer %v was waited on before its " +
						"signaling operation.",
						command_buffer,
						fence,
						location=location,
					) or_return

					signaled_fences[fence] = true
				}
			}
		}
	}

	for fence, waited_on in signaled_fences {
		_check_generic_condition(
			waited_on,
			.Warning,
			"Fence signaled but not waited",
			"The fence %v got signaled but never waited on.",
			fence,
			location=location,
		)
	}

	return nil
}

_check_internal_emission_result :: proc(result: Result, location := #caller_location) -> (res: Result) {
	switch v in result {
	case runtime.Allocator_Error:
		_log_message(
			result,
			.Error,
			"Allocator Error",
			"The internal backend failed a memory operation with the error %v.",
			v,
			location=location,
		)

		return res
	
	case Error:
		#partial switch v {
		case .Invalid_Device, .Invalid_Buffer, .Invalid_Texture, .Invalid_View, .Invalid_Sampler,
			.Invalid_Command_Buffer, .Invalid_Pipeline, .Invalid_Queue, .Invalid_Resource_Set,
			.Invalid_Semaphore, .Invalid_Fence:

			_log_message(
				.Use_After_Free,
				.Error,
				"Use after free",
				"A resource acquisition failed with error %v. This is likely caused by a free " +
				"operation while the resource was still in use.",
				v,
				location=location,
			) or_return
		
		case:
			_log_message(
				result,
				.Error,
				"Internal backend error",
				"The internal backend failed an operation with the error %v.",
				v,
				location=location,
			) or_return
		}

		return res

	case nil:
		return nil
	}

	unreachable()
}

_check_command_buffer_handle :: proc(result: Result, command_buffer: Command_Buffer, location: runtime.Source_Code_Location) -> Result {
	_check_result(
		result,
		.Warning,
		"Invalid resource handle",
		"Invalid command buffer handle (%v).",
		command_buffer,
		location=location,
	) or_return
	return nil
}

_check_in_render_pass :: proc(metadata: ^_Command_Buffer_Metadata, location: runtime.Source_Code_Location) -> Result {
	_check_condition(
		metadata.is_encoding_render_pass,
		.Invalid_Command,
		.Error,
		"Invalid command in encoding context",
		"The issued command is only available when encoding render passes.",
		location=location,
	) or_return
	return nil
}

_check_not_in_render_pass :: proc(
	metadata: ^_Command_Buffer_Metadata,
	location: runtime.Source_Code_Location,
) -> Result {
	_check_condition(
		!metadata.is_encoding_render_pass,
		.Invalid_Command,
		.Error,
		"Invalid command in encoding context",
		"The issued command is only available when not encoding render passes.",
		location=location,
	) or_return
	return nil
}

_command_buffer_metadata_of :: proc(command_buffer: Command_Buffer) -> (^_Command_Buffer_Metadata, Result) {
	sync.shared_guard(&_command_buffers_mutex)

	if command_buffer.index >= len(_command_buffers[command_buffer.queue]) {
		return nil, .Invalid_Command_Buffer
	}

	metadata := &_command_buffers[command_buffer.queue][command_buffer.index]

	if !metadata.in_use || metadata.handle.generation != command_buffer.generation {
		return nil, .Invalid_Command_Buffer
	}

	return metadata, nil
}

_add_command_buffer :: proc(queue: Queue) -> (handle: Command_Buffer, metadata: ^_Command_Buffer_Metadata, res: Result) {
	sync.guard(&_command_buffers_mutex)

	metadatas := &_command_buffers[queue]

	selected: int
	found: bool
	for metadata, i in metadatas {
		if metadata.in_use {
			continue
		}

		selected = i
		found = true
		break
	}

	if !found {
		return {}, nil, .No_Available_Command_Buffers
	}

	metadata = &metadatas[selected]
	metadata.handle.generation += 1
	metadata.in_use = true

	handle = metadata.handle

	return
}

_remove_command_buffer :: proc(command_buffer: Command_Buffer) {
	sync.guard(&_command_buffers_mutex)

	if command_buffer.index >= len(_command_buffers[command_buffer.queue]) {
		return
	}

	metadata := &_command_buffers[command_buffer.queue][command_buffer.index]

	if !metadata.in_use || metadata.handle.generation != command_buffer.generation {
		return
	}

	metadata.in_use = false
}

