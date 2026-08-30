package darwext

import "base:intrinsics"
import NS "core:sys/darwin/Foundation"
import MTL "vendor:darwin/Metal"

@(private)
msgSend :: intrinsics.objc_send

// NOTE: This is not strictly correct, but it is like this to make it compatible with "vendor:darwin/Metal".
Allocation :: NS.Object

@(objc_class="MTLResidencySetDescriptor")
ResidencySetDescriptor :: struct { using _: NS.Copying(ResidencySetDescriptor) }
@(objc_type=ResidencySetDescriptor, objc_name="alloc", objc_is_class_method=true)
ResidencySetDescriptor_alloc :: #force_inline proc "c" () -> ^ResidencySetDescriptor {
	return msgSend(^ResidencySetDescriptor, ResidencySetDescriptor, "alloc")
}
@(objc_type=ResidencySetDescriptor, objc_name="init")
ResidencySetDescriptor_init :: #force_inline proc "c" (self: ^ResidencySetDescriptor) -> ^ResidencySetDescriptor {
	return msgSend(^ResidencySetDescriptor, self, "init")
}
@(objc_type=ResidencySetDescriptor, objc_name="label")
ResidencySetDescriptor_label :: #force_inline proc "c" (self: ^ResidencySetDescriptor) -> ^NS.String {
	return msgSend(^NS.String, self, "label")
}
@(objc_type=ResidencySetDescriptor, objc_name="setLabel")
ResidencySetDescriptor_setLabel :: #force_inline proc "c" (self: ^ResidencySetDescriptor, label: ^NS.String) {
	msgSend(nil, self, "setLabel:", label)
}
@(objc_type=ResidencySetDescriptor, objc_name="initialCapacity")
ResidencySetDescriptor_initialCapacity :: #force_inline proc "c" (self: ^ResidencySetDescriptor) -> u32 {
	return msgSend(u32, self, "initialCapacity")
}
@(objc_type=ResidencySetDescriptor, objc_name="setInitialCapacity")
ResidencySetDescriptor_setInitialCapacity :: #force_inline proc "c" (self: ^ResidencySetDescriptor, initialCapacity: u32) {
	msgSend(nil, self, "setInitialCapacity:", initialCapacity)
}

@(objc_class="MTLResidencySet")
ResidencySet :: struct { using _: NS.Object }
@(objc_type=ResidencySet, objc_name="device")
ResidencySet_device :: #force_inline proc "c" (self: ^ResidencySet) -> ^MTL.Device {
	return msgSend(^MTL.Device, self, "device")
}
@(objc_type=ResidencySet, objc_name="label")
ResidencySet_label :: #force_inline proc "c" (self: ^ResidencySet) -> ^NS.String {
	return msgSend(^NS.String, self, "label")
}
@(objc_type=ResidencySet, objc_name="allocatedSize")
ResidencySet_allocatedSize :: #force_inline proc "c" (self: ^ResidencySet) -> u64 {
	return msgSend(u64, self, "allocatedSize")
}
@(objc_type=ResidencySet, objc_name="requestResidency")
ResidencySet_requestResidency :: #force_inline proc "c" (self: ^ResidencySet) {
	msgSend(nil, self, "requestResidency")
}
@(objc_type=ResidencySet, objc_name="endResidency")
ResidencySet_endResidency :: #force_inline proc "c" (self: ^ResidencySet) {
	msgSend(nil, self, "endResidency")
}
@(objc_type=ResidencySet, objc_name="addAllocation")
ResidencySet_addAllocation :: #force_inline proc "c" (self: ^ResidencySet, allocation: ^NS.Object) {
	msgSend(nil, self, "addAllocation:", allocation)
}
@(objc_type=ResidencySet, objc_name="addAllocations")
ResidencySet_addAllocations :: #force_inline proc "c" (self: ^ResidencySet, allocation: ^NS.Object, count: u32) {
	msgSend(nil, self, "addAllocations:count:", allocation, count)
}
@(objc_type=ResidencySet, objc_name="removeAllocation")
ResidencySet_removeAllocation :: #force_inline proc "c" (self: ^ResidencySet, allocation: ^NS.Object) {
	msgSend(nil, self, "removeAllocation:", allocation)
}
@(objc_type=ResidencySet, objc_name="removeAllocations")
ResidencySet_removeAllocations :: #force_inline proc "c" (self: ^ResidencySet, allocation: [^]^NS.Object, count: u32) {
	msgSend(nil, self, "removeAllocations:count:", allocation, count)
}
@(objc_type=ResidencySet, objc_name="removeAllAllocations")
ResidencySet_removeAllAllocations :: #force_inline proc "c" (self: ^ResidencySet) {
	msgSend(nil, self, "removeAllAllocations")
}
@(objc_type=ResidencySet, objc_name="containsAllocation")
ResidencySet_containsAllocation :: #force_inline proc "c" (self: ^ResidencySet, allocation: ^NS.Object) -> bool {
	return msgSend(bool, self, "containsAllocation:", allocation)
}
@(objc_type=ResidencySet, objc_name="allAllocations")
ResidencySet_allAllocations :: #force_inline proc "c" (self: ^ResidencySet) -> ^NS.Array {
	return msgSend(^NS.Array, self, "allAllocations")
}
@(objc_type=ResidencySet, objc_name="allocationCount")
ResidencySet_allocationCount :: #force_inline proc "c" (self: ^ResidencySet) -> u64 {
	return msgSend(u64, self, "allocationCount")
}
@(objc_type=ResidencySet, objc_name="commit")
ResidencySet_commit :: #force_inline proc "c" (self: ^ResidencySet) {
	msgSend(nil, self, "commit")
}

@(objc_class="MTLEvent")
Event :: struct { using _: NS.Object }
@(objc_class="MTLSharedEvent")
SharedEvent :: struct { using _: Event }
@(objc_type=SharedEvent, objc_name="waitUntilSignaledValue")
SharedEvent_waitUntilSignaledValue :: #force_inline proc "c" (self: ^SharedEvent, value: u64, timeout: u64) -> NS.BOOL {
	return msgSend(NS.BOOL, self, "waitUntilSignaledValue:timeoutMS:", value, timeout)
}

@(objc_class="MTLDevice")
Device :: struct { using _: NS.Object }
@(objc_type=Device, objc_name="newResidencySetWithDescriptor")
Device_newResidencySetWithDescriptor :: #force_inline proc "c" (self: ^Device, descriptor: ^ResidencySetDescriptor, error: ^^NS.Error) -> ^ResidencySet {
	return msgSend(^ResidencySet, self, "newResidencySetWithDescriptor:error:", descriptor, error)
}

@(objc_class="MTLCommandBuffer")
CommandBuffer :: struct { using _: NS.Object }
@(objc_type=CommandBuffer, objc_name="useResidencySet")
CommandBuffer_useResidencySet :: #force_inline proc "c" (self: ^CommandBuffer, residencySet: ^ResidencySet) {
	msgSend(nil, self, "useResidencySet:", residencySet)
}
@(objc_type=CommandBuffer, objc_name="useResidencySets")
CommandBuffer_useResidencySets :: #force_inline proc "c" (self: ^CommandBuffer, residencySets: [^]^ResidencySet, count: u32) {
	msgSend(nil, self, "useResidencySets:", residencySets, count)
}
