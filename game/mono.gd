# A monospace system font, so panels with columns line up.
class_name Mono
extends RefCounted

static var _font: SystemFont


static func font() -> SystemFont:
	if _font == null:
		_font = SystemFont.new()
		_font.font_names = PackedStringArray(["Consolas", "Cascadia Mono", "Courier New", "monospace"])
	return _font
