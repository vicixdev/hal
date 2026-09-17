package clay

// From https://goodpalette.io/b44fe3-b5371b-b5aeb8
// Primary: Ultraviolet Onsible
PRIMARY_100 :: Color{ 254, 242, 255, 255 }
PRIMARY_200 :: Color{ 247, 204, 255, 255 }

PRIMARY_300 :: Color{ 234, 163, 251, 255 }
PRIMARY_400 :: Color{ 212, 122, 243, 255 }
PRIMARY_500 :: Color{ 180,  79, 227, 255 }
PRIMARY_600 :: Color{ 128,  42, 180, 255 }
PRIMARY_700 :: Color{  85,  23, 133, 255 }
PRIMARY_800 :: Color{  50,  13,  80, 255 }
PRIMARY_900 :: Color{  20,   6,  30, 255 }

/* Accent: Bricky Brick */
ACCENT_100 :: Color{ 255, 248, 242, 255 }
ACCENT_200 :: Color{ 254, 213, 190, 255 }
ACCENT_300 :: Color{ 246, 168, 135, 255 }
ACCENT_400 :: Color{ 224, 113,  78, 255 }
ACCENT_500 :: Color{ 181,  55,  27, 255 }
ACCENT_600 :: Color{ 145,  26,   9, 255 }
ACCENT_700 :: Color{ 110,   9,   2, 255 }
ACCENT_800 :: Color{  74,   1,   0, 255 }
ACCENT_900 :: Color{  38,   0,   0, 255 }

/* Neutral */
NEUTRAL_100 :: Color{ 252, 250, 252, 255 }
NEUTRAL_200 :: Color{ 235, 231, 235, 255 }
NEUTRAL_300 :: Color{ 217, 211, 218, 255 }
NEUTRAL_400 :: Color{ 199, 193, 201, 255 }
NEUTRAL_500 :: Color{ 181, 174, 184, 255 }
NEUTRAL_600 :: Color{ 144, 138, 147, 255 }
NEUTRAL_700 :: Color{ 107, 103, 111, 255 }
NEUTRAL_800 :: Color{  71,  68,  75, 255 }
NEUTRAL_900 :: Color{  36,  34,  38, 255 }

WHITE :: Color{ 255, 255, 255, 255 }
BLACK :: Color{   0,   0,   0, 255 }

Font :: proc(font: u16 = 0, size: u16 = 15, color := WHITE) -> TextElementConfig {
	return TextElementConfig{
		textColor	= color,
		fontId		= font,
		fontSize	= size,
	}
}
