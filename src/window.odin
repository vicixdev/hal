package main

import sdl "vendor:sdl3"
import "gfx"

Key :: enum {
	None,

	_1, _2, _3, _4, _5, _6, _7, _8, _9, _0,

	A, B, C, D, E, F, G, H, I, J, K, L, M, N, O, P, Q, R, S, T, U, V, W, X, Y, Z,

	Tilde,
	Grave,
	Exclamation_Mark,
	AT,
	Hash,
	Dollar,
	Percent,
	Caret,
	Ampersand,
	Star,
	Open_Parenthesis,
	Closed_Parenthesis,
	Minus,
	Underscore,
	Plus,
	Equal,
	Open_Bracket,
	Open_Curly,
	Closed_Bracket,
	Closed_Curly,
	Semicolon,
	Colon,
	Apostrophe,
	Quotes,
	Comma,
	Open_Angular,
	Dot,
	Closed_Angular,
	Slash,
	Question_Mark,
	Backslash,
	Pipe,

	Escape,
	Tab,
	Capslock,
	Left_Shift,
	Right_Shift,
	Left_Control,
	Right_Control,
	Left_Alt,
	Right_Alt,
	Left_Meta,
	Right_Meta,
	Space,
	Backspace,
	Enter,

	Left,
	Right,
	Up,
	Down,

	F1, F2, F3, F4, F5, F6, F7, F8, F9, F10, F11, F12,

	Print_Screen,
	Scroll_Lock,
	Pause,
	Insert,
	Home,
	Page_Up,
	Page_Down,
	End,
	Delete,
}

Key_State :: enum {
	Pressed,
	Just_Pressed,
	Just_Released,
}
Key_States :: bit_set[Key_State]

Mouse_Button :: enum {
	None,
	Left,
	Right,
	Middle,
	Lateral_1,
	Lateral_2,
}

Mouse_State :: struct {
	buttons:	[Mouse_Button]Key_States,
	position:	[2]f32,
	delta:		[2]f32,

	captured:	bool,
}

Window_State :: struct {
	dimensions:	[2]int,
	did_resize:	bool,
}

window:		^sdl.Window
window_state :=	Window_State {
	dimensions	= WINDOW_SIZE,
}

key_states:	[Key]Key_States

mouse_state:	Mouse_State

should_quit:	bool

process_events :: proc() {
	window_state.did_resize = false

	for &state in key_states {
		if .Just_Released in state {
			state -= { .Just_Released }
		}
		if .Just_Pressed in state {
			state -= { .Just_Pressed }
		}
	}

	mouse_state.delta = {}

	event: sdl.Event
	for sdl.PollEvent(&event) {
		#partial switch event.type {
		case .QUIT:
			should_quit = true

		case .KEY_UP:
			key_state := &key_states[_sdl_keycode_to_key(event.key.key)]
			key_state^ = { .Just_Released }

		case .KEY_DOWN:
			key_state := &key_states[_sdl_keycode_to_key(event.key.key)]
			key_state^ = { .Pressed, .Just_Pressed }

		case .MOUSE_BUTTON_UP:
			key_state := &mouse_state.buttons[_SDL_BUTTON_INDEX_TO_MOUSE_BUTTON[event.button.button]]
			key_state^ = { .Just_Released }

		case .MOUSE_BUTTON_DOWN:
			key_state := &mouse_state.buttons[_SDL_BUTTON_INDEX_TO_MOUSE_BUTTON[event.button.button]]
			key_state^ = { .Pressed, .Just_Pressed }

		case .MOUSE_MOTION:
			mouse_state.delta = {
				event.motion.xrel, event.motion.yrel,
			}
			mouse_state.position = {
				event.motion.x, event.motion.y,
			}

		case .WINDOW_RESIZED:
			window_state.dimensions = { cast(int)event.window.data1, cast(int)event.window.data2 }
			gfx.resize_surface(surface, window_state.dimensions)

			window_state.did_resize = true
		}
	}
}

toggle_mouse_capture :: proc() {
	mouse_state.captured = !mouse_state.captured
	_ = sdl.SetWindowRelativeMouseMode(window, mouse_state.captured)
}

_sdl_keycode_to_key :: proc(keycode: sdl.Keycode) -> Key {
	LOOKUP_0x0_BASE :: 0x0
	@(static, rodata)
	LOOKUP_0x0 := #partial [?]Key {
		sdl.K_UNKNOWN			- LOOKUP_0x0_BASE	= .None,
		sdl.K_RETURN			- LOOKUP_0x0_BASE	= .Enter,
		sdl.K_ESCAPE			- LOOKUP_0x0_BASE	= .Escape,
		sdl.K_BACKSPACE			- LOOKUP_0x0_BASE	= .Backspace,
		sdl.K_TAB			- LOOKUP_0x0_BASE	= .Tab,
		sdl.K_SPACE			- LOOKUP_0x0_BASE	= .Space,
		sdl.K_EXCLAIM			- LOOKUP_0x0_BASE	= .Exclamation_Mark,
		sdl.K_DBLAPOSTROPHE		- LOOKUP_0x0_BASE	= .Apostrophe,
		sdl.K_HASH			- LOOKUP_0x0_BASE	= .Hash,
		sdl.K_DOLLAR			- LOOKUP_0x0_BASE	= .Dollar,
		sdl.K_PERCENT			- LOOKUP_0x0_BASE	= .Percent,
		sdl.K_AMPERSAND			- LOOKUP_0x0_BASE	= .Ampersand,
		sdl.K_APOSTROPHE		- LOOKUP_0x0_BASE	= .Apostrophe,
		sdl.K_LEFTPAREN			- LOOKUP_0x0_BASE	= .Open_Parenthesis,
		sdl.K_RIGHTPAREN		- LOOKUP_0x0_BASE	= .Closed_Parenthesis,
		sdl.K_ASTERISK			- LOOKUP_0x0_BASE	= .Star,
		sdl.K_PLUS			- LOOKUP_0x0_BASE	= .Plus,
		sdl.K_COMMA			- LOOKUP_0x0_BASE	= .Comma,
		sdl.K_MINUS			- LOOKUP_0x0_BASE	= .Minus,
		sdl.K_PERIOD			- LOOKUP_0x0_BASE	= .Dot,
		sdl.K_SLASH			- LOOKUP_0x0_BASE	= .Slash,
		sdl.K_0				- LOOKUP_0x0_BASE	= ._0,
		sdl.K_1				- LOOKUP_0x0_BASE	= ._1,
		sdl.K_2				- LOOKUP_0x0_BASE	= ._2,
		sdl.K_3				- LOOKUP_0x0_BASE	= ._3,
		sdl.K_4				- LOOKUP_0x0_BASE	= ._4,
		sdl.K_5				- LOOKUP_0x0_BASE	= ._5,
		sdl.K_6				- LOOKUP_0x0_BASE	= ._6,
		sdl.K_7				- LOOKUP_0x0_BASE	= ._7,
		sdl.K_8				- LOOKUP_0x0_BASE	= ._8,
		sdl.K_9				- LOOKUP_0x0_BASE	= ._9,
		sdl.K_COLON			- LOOKUP_0x0_BASE	= .Colon,
		sdl.K_SEMICOLON			- LOOKUP_0x0_BASE	= .Semicolon,
		sdl.K_LESS			- LOOKUP_0x0_BASE	= .Open_Angular,
		sdl.K_EQUALS			- LOOKUP_0x0_BASE	= .Equal,
		sdl.K_GREATER			- LOOKUP_0x0_BASE	= .Closed_Angular,
		sdl.K_QUESTION			- LOOKUP_0x0_BASE	= .Question_Mark,
		sdl.K_AT			- LOOKUP_0x0_BASE	= .AT,
		sdl.K_LEFTBRACKET		- LOOKUP_0x0_BASE	= .Open_Bracket,
		sdl.K_BACKSLASH			- LOOKUP_0x0_BASE	= .Backslash,
		sdl.K_RIGHTBRACKET		- LOOKUP_0x0_BASE	= .Closed_Bracket,
		sdl.K_CARET			- LOOKUP_0x0_BASE	= .Caret,
		sdl.K_UNDERSCORE		- LOOKUP_0x0_BASE	= .Underscore,
		sdl.K_GRAVE			- LOOKUP_0x0_BASE	= .Grave,
		sdl.K_A				- LOOKUP_0x0_BASE	= .A,
		sdl.K_B				- LOOKUP_0x0_BASE	= .B,
		sdl.K_C				- LOOKUP_0x0_BASE	= .C,
		sdl.K_D				- LOOKUP_0x0_BASE	= .D,
		sdl.K_E				- LOOKUP_0x0_BASE	= .E,
		sdl.K_F				- LOOKUP_0x0_BASE	= .F,
		sdl.K_G				- LOOKUP_0x0_BASE	= .G,
		sdl.K_H				- LOOKUP_0x0_BASE	= .H,
		sdl.K_I				- LOOKUP_0x0_BASE	= .I,
		sdl.K_J				- LOOKUP_0x0_BASE	= .J,
		sdl.K_K				- LOOKUP_0x0_BASE	= .K,
		sdl.K_L				- LOOKUP_0x0_BASE	= .L,
		sdl.K_M				- LOOKUP_0x0_BASE	= .M,
		sdl.K_N				- LOOKUP_0x0_BASE	= .N,
		sdl.K_O				- LOOKUP_0x0_BASE	= .O,
		sdl.K_P				- LOOKUP_0x0_BASE	= .P,
		sdl.K_Q				- LOOKUP_0x0_BASE	= .Q,
		sdl.K_R				- LOOKUP_0x0_BASE	= .R,
		sdl.K_S				- LOOKUP_0x0_BASE	= .S,
		sdl.K_T				- LOOKUP_0x0_BASE	= .T,
		sdl.K_U				- LOOKUP_0x0_BASE	= .U,
		sdl.K_V				- LOOKUP_0x0_BASE	= .V,
		sdl.K_W				- LOOKUP_0x0_BASE	= .W,
		sdl.K_X				- LOOKUP_0x0_BASE	= .X,
		sdl.K_Y				- LOOKUP_0x0_BASE	= .Y,
		sdl.K_Z				- LOOKUP_0x0_BASE	= .Z,
		sdl.K_LEFTBRACE			- LOOKUP_0x0_BASE	= .Open_Curly,
		sdl.K_PIPE			- LOOKUP_0x0_BASE	= .Pipe,
		sdl.K_RIGHTBRACE		- LOOKUP_0x0_BASE	= .Closed_Curly,
		sdl.K_TILDE			- LOOKUP_0x0_BASE	= .Tilde,
		sdl.K_DELETE			- LOOKUP_0x0_BASE	= .Delete,
		sdl.K_PLUSMINUS			- LOOKUP_0x0_BASE	= .None,
	}

	LOOKUP_0x2_BASE :: 0x20000000
	@(static, rodata)
	LOOKUP_0x2 := #partial [?]Key {
		sdl.K_LEFT_TAB			- LOOKUP_0x4_BASE	= .Tab,
		sdl.K_LEVEL5_SHIFT		- LOOKUP_0x4_BASE	= .Left_Shift,
		sdl.K_MULTI_KEY_COMPOSE		- LOOKUP_0x4_BASE	= .None,
		sdl.K_LMETA			- LOOKUP_0x4_BASE	= .Left_Meta,
		sdl.K_RMETA			- LOOKUP_0x4_BASE	= .Right_Meta,
		sdl.K_LHYPER			- LOOKUP_0x4_BASE	= .Left_Meta,
		sdl.K_RHYPER			- LOOKUP_0x4_BASE	= .Right_Meta,
	}

	LOOKUP_0x4_BASE :: 0x40000000
	@(static, rodata)
	LOOKUP_0x4 := #partial [?]Key {
		sdl.K_CAPSLOCK			- LOOKUP_0x4_BASE	= .Capslock,
		sdl.K_F1			- LOOKUP_0x4_BASE	= .F1,
		sdl.K_F2			- LOOKUP_0x4_BASE	= .F2,
		sdl.K_F3			- LOOKUP_0x4_BASE	= .F3,
		sdl.K_F4			- LOOKUP_0x4_BASE	= .F4,
		sdl.K_F5			- LOOKUP_0x4_BASE	= .F5,
		sdl.K_F6			- LOOKUP_0x4_BASE	= .F6,
		sdl.K_F7			- LOOKUP_0x4_BASE	= .F7,
		sdl.K_F8			- LOOKUP_0x4_BASE	= .F8,
		sdl.K_F9			- LOOKUP_0x4_BASE	= .F9,
		sdl.K_F10			- LOOKUP_0x4_BASE	= .F10,
		sdl.K_F11			- LOOKUP_0x4_BASE	= .F11,
		sdl.K_F12			- LOOKUP_0x4_BASE	= .F12,
		sdl.K_PRINTSCREEN		- LOOKUP_0x4_BASE	= .Print_Screen,
		sdl.K_SCROLLLOCK		- LOOKUP_0x4_BASE	= .Scroll_Lock,
		sdl.K_PAUSE			- LOOKUP_0x4_BASE	= .Pause,
		sdl.K_INSERT			- LOOKUP_0x4_BASE	= .Insert,
		sdl.K_HOME			- LOOKUP_0x4_BASE	= .Home,
		sdl.K_PAGEUP			- LOOKUP_0x4_BASE	= .Page_Up,
		sdl.K_END			- LOOKUP_0x4_BASE	= .End,
		sdl.K_PAGEDOWN			- LOOKUP_0x4_BASE	= .Page_Down,
		sdl.K_RIGHT			- LOOKUP_0x4_BASE	= .Right,
		sdl.K_LEFT			- LOOKUP_0x4_BASE	= .Left,
		sdl.K_DOWN			- LOOKUP_0x4_BASE	= .Down,
		sdl.K_UP			- LOOKUP_0x4_BASE	= .Up,
		sdl.K_NUMLOCKCLEAR		- LOOKUP_0x4_BASE	= .None,
		sdl.K_KP_DIVIDE			- LOOKUP_0x4_BASE	= .Slash,
		sdl.K_KP_MULTIPLY		- LOOKUP_0x4_BASE	= .Star,
		sdl.K_KP_MINUS			- LOOKUP_0x4_BASE	= .Minus,
		sdl.K_KP_PLUS			- LOOKUP_0x4_BASE	= .Plus,
		sdl.K_KP_ENTER			- LOOKUP_0x4_BASE	= .Enter,
		sdl.K_KP_1			- LOOKUP_0x4_BASE	= ._1,
		sdl.K_KP_2			- LOOKUP_0x4_BASE	= ._2,
		sdl.K_KP_3			- LOOKUP_0x4_BASE	= ._3,
		sdl.K_KP_4			- LOOKUP_0x4_BASE	= ._4,
		sdl.K_KP_5			- LOOKUP_0x4_BASE	= ._5,
		sdl.K_KP_6			- LOOKUP_0x4_BASE	= ._6,
		sdl.K_KP_7			- LOOKUP_0x4_BASE	= ._7,
		sdl.K_KP_8			- LOOKUP_0x4_BASE	= ._8,
		sdl.K_KP_9			- LOOKUP_0x4_BASE	= ._9,
		sdl.K_KP_0			- LOOKUP_0x4_BASE	= ._0,
		sdl.K_KP_PERIOD			- LOOKUP_0x4_BASE	= .Dot,
		sdl.K_APPLICATION		- LOOKUP_0x4_BASE	= .None,
		sdl.K_POWER			- LOOKUP_0x4_BASE	= .Caret,
		sdl.K_KP_EQUALS			- LOOKUP_0x4_BASE	= .Equal,
		sdl.K_F13			- LOOKUP_0x4_BASE	= .None,
		sdl.K_F14			- LOOKUP_0x4_BASE	= .None,
		sdl.K_F15			- LOOKUP_0x4_BASE	= .None,
		sdl.K_F16			- LOOKUP_0x4_BASE	= .None,
		sdl.K_F17			- LOOKUP_0x4_BASE	= .None,
		sdl.K_F18			- LOOKUP_0x4_BASE	= .None,
		sdl.K_F19			- LOOKUP_0x4_BASE	= .None,
		sdl.K_F20			- LOOKUP_0x4_BASE	= .None,
		sdl.K_F21			- LOOKUP_0x4_BASE	= .None,
		sdl.K_F22			- LOOKUP_0x4_BASE	= .None,
		sdl.K_F23			- LOOKUP_0x4_BASE	= .None,
		sdl.K_F24			- LOOKUP_0x4_BASE	= .None,
		sdl.K_EXECUTE			- LOOKUP_0x4_BASE	= .None,
		sdl.K_HELP			- LOOKUP_0x4_BASE	= .None,
		sdl.K_MENU			- LOOKUP_0x4_BASE	= .None,
		sdl.K_SELECT			- LOOKUP_0x4_BASE	= .None,
		sdl.K_STOP			- LOOKUP_0x4_BASE	= .None,
		sdl.K_AGAIN			- LOOKUP_0x4_BASE	= .None,
		sdl.K_UNDO			- LOOKUP_0x4_BASE	= .None,
		sdl.K_CUT			- LOOKUP_0x4_BASE	= .None,
		sdl.K_COPY			- LOOKUP_0x4_BASE	= .None,
		sdl.K_PASTE			- LOOKUP_0x4_BASE	= .None,
		sdl.K_FIND			- LOOKUP_0x4_BASE	= .None,
		sdl.K_MUTE			- LOOKUP_0x4_BASE	= .None,
		sdl.K_VOLUMEUP			- LOOKUP_0x4_BASE	= .None,
		sdl.K_VOLUMEDOWN		- LOOKUP_0x4_BASE	= .None,
		sdl.K_KP_COMMA			- LOOKUP_0x4_BASE	= .Comma,
		sdl.K_KP_EQUALSAS400		- LOOKUP_0x4_BASE	= .Equal,
		sdl.K_ALTERASE			- LOOKUP_0x4_BASE	= .Delete,
		sdl.K_SYSREQ			- LOOKUP_0x4_BASE	= .None,
		sdl.K_CANCEL			- LOOKUP_0x4_BASE	= .Delete,
		sdl.K_CLEAR			- LOOKUP_0x4_BASE	= .Delete,
		sdl.K_PRIOR			- LOOKUP_0x4_BASE	= .None,
		sdl.K_RETURN2			- LOOKUP_0x4_BASE	= .None,
		sdl.K_SEPARATOR			- LOOKUP_0x4_BASE	= .None,
		sdl.K_OUT			- LOOKUP_0x4_BASE	= .None,
		sdl.K_OPER			- LOOKUP_0x4_BASE	= .None,
		sdl.K_CLEARAGAIN		- LOOKUP_0x4_BASE	= .Delete,
		sdl.K_CRSEL			- LOOKUP_0x4_BASE	= .None,
		sdl.K_EXSEL			- LOOKUP_0x4_BASE	= .None,
		sdl.K_KP_00			- LOOKUP_0x4_BASE	= ._0,
		sdl.K_KP_000			- LOOKUP_0x4_BASE	= ._0,
		sdl.K_THOUSANDSSEPARATOR	- LOOKUP_0x4_BASE	= .None,
		sdl.K_DECIMALSEPARATOR		- LOOKUP_0x4_BASE	= .None,
		sdl.K_CURRENCYUNIT		- LOOKUP_0x4_BASE	= .None,
		sdl.K_CURRENCYSUBUNIT		- LOOKUP_0x4_BASE	= .None,
		sdl.K_KP_LEFTPAREN		- LOOKUP_0x4_BASE	= .Open_Parenthesis,
		sdl.K_KP_RIGHTPAREN		- LOOKUP_0x4_BASE	= .Closed_Parenthesis,
		sdl.K_KP_LEFTBRACE		- LOOKUP_0x4_BASE	= .Open_Bracket,
		sdl.K_KP_RIGHTBRACE		- LOOKUP_0x4_BASE	= .Closed_Bracket,
		sdl.K_KP_TAB			- LOOKUP_0x4_BASE	= .Tab,
		sdl.K_KP_BACKSPACE		- LOOKUP_0x4_BASE	= .Backspace,
		sdl.K_KP_A			- LOOKUP_0x4_BASE	= .A,
		sdl.K_KP_B			- LOOKUP_0x4_BASE	= .B,
		sdl.K_KP_C			- LOOKUP_0x4_BASE	= .C,
		sdl.K_KP_D			- LOOKUP_0x4_BASE	= .D,
		sdl.K_KP_E			- LOOKUP_0x4_BASE	= .E,
		sdl.K_KP_F			- LOOKUP_0x4_BASE	= .F,
		sdl.K_KP_XOR			- LOOKUP_0x4_BASE	= .None,
		sdl.K_KP_POWER			- LOOKUP_0x4_BASE	= .Caret,
		sdl.K_KP_PERCENT		- LOOKUP_0x4_BASE	= .Percent,
		sdl.K_KP_LESS			- LOOKUP_0x4_BASE	= .Open_Angular,
		sdl.K_KP_GREATER		- LOOKUP_0x4_BASE	= .Closed_Angular,
		sdl.K_KP_AMPERSAND		- LOOKUP_0x4_BASE	= .Ampersand,
		sdl.K_KP_DBLAMPERSAND		- LOOKUP_0x4_BASE	= .Ampersand,
		sdl.K_KP_VERTICALBAR		- LOOKUP_0x4_BASE	= .Pipe,
		sdl.K_KP_DBLVERTICALBAR		- LOOKUP_0x4_BASE	= .Pipe,
		sdl.K_KP_COLON			- LOOKUP_0x4_BASE	= .Colon,
		sdl.K_KP_HASH			- LOOKUP_0x4_BASE	= .Hash,
		sdl.K_KP_SPACE			- LOOKUP_0x4_BASE	= .Space,
		sdl.K_KP_AT			- LOOKUP_0x4_BASE	= .AT,
		sdl.K_KP_EXCLAM			- LOOKUP_0x4_BASE	= .Exclamation_Mark,
		sdl.K_KP_MEMSTORE		- LOOKUP_0x4_BASE	= .None,
		sdl.K_KP_MEMRECALL		- LOOKUP_0x4_BASE	= .None,
		sdl.K_KP_MEMCLEAR		- LOOKUP_0x4_BASE	= .Delete,
		sdl.K_KP_MEMADD			- LOOKUP_0x4_BASE	= .Plus,
		sdl.K_KP_MEMSUBTRACT		- LOOKUP_0x4_BASE	= .Minus,
		sdl.K_KP_MEMMULTIPLY		- LOOKUP_0x4_BASE	= .Star,
		sdl.K_KP_MEMDIVIDE		- LOOKUP_0x4_BASE	= .Slash,
		sdl.K_KP_PLUSMINUS		- LOOKUP_0x4_BASE	= .None,
		sdl.K_KP_CLEAR			- LOOKUP_0x4_BASE	= .Delete,
		sdl.K_KP_CLEARENTRY		- LOOKUP_0x4_BASE	= .Delete,
		sdl.K_KP_BINARY			- LOOKUP_0x4_BASE	= .None,
		sdl.K_KP_OCTAL			- LOOKUP_0x4_BASE	= .None,
		sdl.K_KP_DECIMAL		- LOOKUP_0x4_BASE	= .None,
		sdl.K_KP_HEXADECIMAL		- LOOKUP_0x4_BASE	= .None,
		sdl.K_LCTRL			- LOOKUP_0x4_BASE	= .Left_Control,
		sdl.K_LSHIFT			- LOOKUP_0x4_BASE	= .Left_Shift,
		sdl.K_LALT			- LOOKUP_0x4_BASE	= .Left_Alt,
		sdl.K_LGUI			- LOOKUP_0x4_BASE	= .Left_Meta,
		sdl.K_RCTRL			- LOOKUP_0x4_BASE	= .Right_Control,
		sdl.K_RSHIFT			- LOOKUP_0x4_BASE	= .Right_Shift,
		sdl.K_RALT			- LOOKUP_0x4_BASE	= .Right_Alt,
		sdl.K_RGUI			- LOOKUP_0x4_BASE	= .Right_Meta,
		sdl.K_MODE			- LOOKUP_0x4_BASE	= .None,
		sdl.K_SLEEP			- LOOKUP_0x4_BASE	= .None,
		sdl.K_WAKE			- LOOKUP_0x4_BASE	= .None,
		sdl.K_CHANNEL_INCREMENT		- LOOKUP_0x4_BASE	= .None,
		sdl.K_CHANNEL_DECREMENT		- LOOKUP_0x4_BASE	= .None,
		sdl.K_MEDIA_PLAY		- LOOKUP_0x4_BASE	= .None,
		sdl.K_MEDIA_PAUSE		- LOOKUP_0x4_BASE	= .None,
		sdl.K_MEDIA_RECORD		- LOOKUP_0x4_BASE	= .None,
		sdl.K_MEDIA_FAST_FORWARD	- LOOKUP_0x4_BASE	= .None,
		sdl.K_MEDIA_REWIND		- LOOKUP_0x4_BASE	= .None,
		sdl.K_MEDIA_NEXT_TRACK		- LOOKUP_0x4_BASE	= .None,
		sdl.K_MEDIA_PREVIOUS_TRACK	- LOOKUP_0x4_BASE	= .None,
		sdl.K_MEDIA_STOP		- LOOKUP_0x4_BASE	= .None,
		sdl.K_MEDIA_EJECT		- LOOKUP_0x4_BASE	= .None,
		sdl.K_MEDIA_PLAY_PAUSE		- LOOKUP_0x4_BASE	= .None,
		sdl.K_MEDIA_SELECT		- LOOKUP_0x4_BASE	= .None,
		sdl.K_AC_NEW			- LOOKUP_0x4_BASE	= .None,
		sdl.K_AC_OPEN			- LOOKUP_0x4_BASE	= .None,
		sdl.K_AC_CLOSE			- LOOKUP_0x4_BASE	= .None,
		sdl.K_AC_EXIT			- LOOKUP_0x4_BASE	= .None,
		sdl.K_AC_SAVE			- LOOKUP_0x4_BASE	= .None,
		sdl.K_AC_PRINT			- LOOKUP_0x4_BASE	= .None,
		sdl.K_AC_PROPERTIES		- LOOKUP_0x4_BASE	= .None,
		sdl.K_AC_SEARCH			- LOOKUP_0x4_BASE	= .None,
		sdl.K_AC_HOME			- LOOKUP_0x4_BASE	= .None,
		sdl.K_AC_BACK			- LOOKUP_0x4_BASE	= .None,
		sdl.K_AC_FORWARD		- LOOKUP_0x4_BASE	= .None,
		sdl.K_AC_STOP			- LOOKUP_0x4_BASE	= .None,
		sdl.K_AC_REFRESH		- LOOKUP_0x4_BASE	= .None,
		sdl.K_AC_BOOKMARKS		- LOOKUP_0x4_BASE	= .None,
		sdl.K_SOFTLEFT			- LOOKUP_0x4_BASE	= .Left,
		sdl.K_SOFTRIGHT			- LOOKUP_0x4_BASE	= .Right,
		sdl.K_CALL			- LOOKUP_0x4_BASE	= .None,
		sdl.K_ENDCALL			- LOOKUP_0x4_BASE	= .None,
	}

	if keycode >= LOOKUP_0x0_BASE && keycode < LOOKUP_0x2_BASE {
		return LOOKUP_0x0[keycode - LOOKUP_0x0_BASE]
	} else if keycode >= LOOKUP_0x2_BASE && keycode < LOOKUP_0x4_BASE {
		return LOOKUP_0x2[keycode - LOOKUP_0x2_BASE]
	} else {
		return LOOKUP_0x4[keycode - LOOKUP_0x4_BASE]
	}
}

@(rodata)
_SDL_BUTTON_INDEX_TO_MOUSE_BUTTON := [?]Mouse_Button {
	sdl.BUTTON_LEFT		= .Left,
	sdl.BUTTON_RIGHT	= .Right,
	sdl.BUTTON_MIDDLE	= .Middle,
	sdl.BUTTON_X1		= .Lateral_1,
	sdl.BUTTON_X2		= .Lateral_2,
}

