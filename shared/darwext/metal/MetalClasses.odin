package darwext

import "base:intrinsics"
import NS "core:sys/darwin/Foundation"

@(private)
msgSend :: intrinsics.objc_send

@(objc_class="MTLEvent")
Event :: struct { using _: NS.Object }
@(objc_class="MTLSharedEvent")
SharedEvent :: struct { using _: Event }

@(objc_type=SharedEvent, objc_name="waitUntilSignaledValue")
SharedEvent_waitUntilSignaledValue :: #force_inline proc "c" (self: ^SharedEvent, value: u64, timeout: u64) -> NS.BOOL {
	return msgSend(NS.BOOL, self, "waitUntilSignaledValue:timeoutMS:", value, timeout)
}

