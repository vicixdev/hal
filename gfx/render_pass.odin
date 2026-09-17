/*
This Source Code Form is subject to the terms of the Mozilla Public
License, v. 2.0. If a copy of the MPL was not distributed with this
file, You can obtain one at https://mozilla.org/MPL/2.0/.
*/

package vicixdev_gfx

Load_Operation :: enum {
	Clear,
	Load,
	Dont_Care,
}

Store_Operation :: enum {
	Store,
	Dont_Care,
}

Clear_Value :: union {
	f64,	// Depth clear value
	u32,	// Stencil clear value
	[4]f64,	// Color clear value
}

Render_Attachment :: struct {
	view:			View,
	resolve_view:		View,
	load_operation:		Load_Operation,
	store_operation:	Store_Operation,
	clear_value:		Clear_Value,
}

Render_Pass_Descriptor :: struct {
	depth_attachment:	Maybe(Render_Attachment),
	stencil_attachment:	Maybe(Render_Attachment),
	color_attachments:	[]Render_Attachment,
}

