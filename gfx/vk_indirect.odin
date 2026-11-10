package vicixdev_gfx

_vk_Indirect_Command_Pool_Metadata :: struct {}

_vk_create_indirect_command_pool :: proc(
	metadata:	^_Indirect_Command_Pool_Metadata,
	descriptor:	Indirect_Command_Pool_Descriptor,
) -> Result {
	unimplemented()
}

_vk_destroy_indirect_command_pool :: proc(metadata: ^_Indirect_Command_Pool_Metadata) {
	unimplemented()
}

_vk_prepare_indirect_command :: proc(
	icp_metadata:	^_Indirect_Command_Pool_Metadata,
	ic_metadata:	^_Indirect_Command_Metadata,
) -> Result {
	unimplemented()
}

_vk_emit_encode_indirect :: proc(
	metadata:	^_Command_Buffer_Metadata,
	queue_metadata:	^_Queue_Metadata,
	command:	_Command_Encode_Indirect,
) -> Result {
	unimplemented()
}

_vk_emit_execute_indirect :: proc(
	metadata:	^_Command_Buffer_Metadata,
	queue_metadata:	^_Queue_Metadata,
	command:	_Command_Execute_Indirect,
) -> Result {
	unimplemented()
}

