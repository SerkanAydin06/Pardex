extends RefCounted

# PARDEX visual language: colors, panel/button styles and small widget
# factories shared by the shell and every page, so all screens match the
# reference design (dark navy surfaces, cyan accent, rounded cards).

const BG := Color("070b14")
const SIDEBAR := Color("0a101c")
const SURFACE := Color("0f1726")
const SURFACE_2 := Color("131d2f")
const BORDER := Color("1c2a40")
const BORDER_HI := Color("2a4a70")
const ACCENT := Color("2aa8ff")
const ACCENT_DARK := Color("0f6fb8")
const GOLD := Color("f2b544")
const TEXT := Color("e8eef8")
const TEXT_2 := Color("9aa8bd")
const TEXT_3 := Color("67748a")
const GREEN := Color("3ed27a")
const AMBER := Color("f0b84f")
const RED := Color("ff6b63")
const CYAN := Color("5fd0ff")


static func box(bg: Color, radius := 12, border := Color.TRANSPARENT, border_width := 0, pad := 0) -> StyleBoxFlat:
	var style := StyleBoxFlat.new()
	style.bg_color = bg
	style.set_corner_radius_all(radius)
	if border_width > 0:
		style.border_color = border
		style.set_border_width_all(border_width)
	style.set_content_margin_all(pad)
	style.anti_aliasing = true
	return style


static func card_style(pad := 14) -> StyleBoxFlat:
	return box(SURFACE, 12, BORDER, 1, pad)


static func panel(pad := 14, style: StyleBox = null) -> PanelContainer:
	var container := PanelContainer.new()
	container.add_theme_stylebox_override("panel", style if style != null else card_style(pad))
	return container


static func label(text: String, size := 14, color := TEXT, bold := false) -> Label:
	var item := Label.new()
	item.text = text
	item.add_theme_font_size_override("font_size", size)
	item.add_theme_color_override("font_color", color)
	if bold:
		item.add_theme_constant_override("outline_size", 1)
		item.add_theme_color_override("font_outline_color", color)
	return item


# Single-line text that may be cut with "…" when its row is narrow. Only use it
# where the parent chain gives the label the row's full width.
static func fit(item: Label) -> Label:
	item.text_overrun_behavior = TextServer.OVERRUN_TRIM_ELLIPSIS
	return item


static func vbox(separation := 8) -> VBoxContainer:
	var container := VBoxContainer.new()
	container.add_theme_constant_override("separation", separation)
	return container


static func hbox(separation := 8) -> HBoxContainer:
	var container := HBoxContainer.new()
	container.add_theme_constant_override("separation", separation)
	return container


static func spacer() -> Control:
	var item := Control.new()
	item.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	item.mouse_filter = Control.MOUSE_FILTER_IGNORE
	return item


static func expand(control: Control, ratio := 1.0) -> Control:
	control.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	control.size_flags_stretch_ratio = ratio
	return control


# kind: "primary" (cyan), "gold", "ghost" (dark outline), "link" (text only)
static func button(text: String, kind := "primary", font_size := 13, height := 36.0) -> Button:
	var item := Button.new()
	item.text = text
	item.focus_mode = Control.FOCUS_NONE
	item.mouse_default_cursor_shape = Control.CURSOR_POINTING_HAND
	item.custom_minimum_size.y = height
	item.add_theme_font_size_override("font_size", font_size)
	var bg := ACCENT
	var fg := Color("04121f")
	var border := Color.TRANSPARENT
	match kind:
		"gold":
			bg = GOLD
			fg = Color("1d1403")
		"ghost":
			bg = Color(1, 1, 1, 0.04)
			fg = TEXT
			border = BORDER_HI
		"link":
			bg = Color.TRANSPARENT
			fg = ACCENT
	var normal := box(bg, 8, border, 1 if border.a > 0 else 0)
	normal.content_margin_left = 16
	normal.content_margin_right = 16
	var hover := normal.duplicate() as StyleBoxFlat
	hover.bg_color = bg.lightened(0.12) if kind != "link" else Color(1, 1, 1, 0.04)
	var disabled := normal.duplicate() as StyleBoxFlat
	disabled.bg_color = Color(1, 1, 1, 0.05) if kind != "link" else Color.TRANSPARENT
	disabled.border_color = BORDER
	item.add_theme_stylebox_override("normal", normal)
	item.add_theme_stylebox_override("hover", hover)
	item.add_theme_stylebox_override("pressed", hover)
	item.add_theme_stylebox_override("disabled", disabled)
	item.add_theme_color_override("font_color", fg)
	item.add_theme_color_override("font_hover_color", fg)
	item.add_theme_color_override("font_pressed_color", fg)
	item.add_theme_color_override("font_disabled_color", TEXT_3)
	return item


static func icon_button(text: String, tooltip := "", size := 34.0) -> Button:
	var item := Button.new()
	item.text = text
	item.tooltip_text = tooltip
	item.focus_mode = Control.FOCUS_NONE
	item.mouse_default_cursor_shape = Control.CURSOR_POINTING_HAND
	item.custom_minimum_size = Vector2(size, size)
	item.add_theme_font_size_override("font_size", 15)
	item.add_theme_color_override("font_color", TEXT_2)
	item.add_theme_color_override("font_hover_color", TEXT)
	var normal := box(Color(1, 1, 1, 0.0), 8)
	var hover := box(Color(1, 1, 1, 0.07), 8)
	item.add_theme_stylebox_override("normal", normal)
	item.add_theme_stylebox_override("hover", hover)
	item.add_theme_stylebox_override("pressed", hover)
	item.add_theme_stylebox_override("disabled", normal)
	return item


static func chip(text: String, active := false, font_size := 12) -> Button:
	var item := Button.new()
	item.text = text
	item.toggle_mode = true
	item.button_pressed = active
	item.focus_mode = Control.FOCUS_NONE
	item.mouse_default_cursor_shape = Control.CURSOR_POINTING_HAND
	item.custom_minimum_size.y = 30
	item.add_theme_font_size_override("font_size", font_size)
	var normal := box(SURFACE_2, 8, BORDER, 1)
	normal.content_margin_left = 14
	normal.content_margin_right = 14
	var on := box(ACCENT, 8)
	on.content_margin_left = 14
	on.content_margin_right = 14
	var hover := normal.duplicate() as StyleBoxFlat
	hover.border_color = BORDER_HI
	item.add_theme_stylebox_override("normal", normal)
	item.add_theme_stylebox_override("hover", hover)
	item.add_theme_stylebox_override("pressed", on)
	item.add_theme_stylebox_override("hover_pressed", on)
	item.add_theme_color_override("font_color", TEXT_2)
	item.add_theme_color_override("font_hover_color", TEXT)
	item.add_theme_color_override("font_pressed_color", Color("04121f"))
	item.add_theme_color_override("font_hover_pressed_color", Color("04121f"))
	return item


static func tag(text: String, color := ACCENT, font_size := 10) -> PanelContainer:
	var style := box(Color(color, 0.16), 5, Color(color, 0.55), 1)
	style.content_margin_left = 8
	style.content_margin_right = 8
	style.content_margin_top = 2
	style.content_margin_bottom = 2
	var holder := panel(0, style)
	holder.size_flags_horizontal = Control.SIZE_SHRINK_BEGIN
	holder.add_child(label(text, font_size, color.lightened(0.35)))
	return holder


static func search_field(placeholder: String, height := 36.0) -> LineEdit:
	var field := LineEdit.new()
	field.placeholder_text = placeholder
	field.custom_minimum_size.y = height
	field.clear_button_enabled = true
	field.add_theme_font_size_override("font_size", 13)
	field.add_theme_color_override("font_color", TEXT)
	field.add_theme_color_override("font_placeholder_color", TEXT_3)
	var normal := box(SURFACE_2, 9, BORDER, 1)
	normal.content_margin_left = 34
	normal.content_margin_right = 10
	var focus := normal.duplicate() as StyleBoxFlat
	focus.border_color = ACCENT_DARK
	field.add_theme_stylebox_override("normal", normal)
	field.add_theme_stylebox_override("focus", focus)
	field.add_theme_stylebox_override("read_only", normal)
	var glass := label("⌕", 17, TEXT_3)
	glass.set_anchors_preset(Control.PRESET_CENTER_LEFT)
	glass.offset_left = 12
	glass.offset_top = -12
	glass.offset_bottom = 12
	glass.mouse_filter = Control.MOUSE_FILTER_IGNORE
	field.add_child(glass)
	return field


# Rounded image (poster/banner/thumbnail) that fills its box, cropping to cover.
static func image(texture: Texture2D, min_size := Vector2.ZERO, radius := 10) -> PanelContainer:
	var frame := PanelContainer.new()
	frame.clip_children = CanvasItem.CLIP_CHILDREN_AND_DRAW
	frame.custom_minimum_size = min_size
	frame.add_theme_stylebox_override("panel", box(SURFACE_2, radius))
	var rect := TextureRect.new()
	rect.texture = texture
	rect.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	rect.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_COVERED
	rect.texture_filter = CanvasItem.TEXTURE_FILTER_LINEAR_WITH_MIPMAPS
	rect.mouse_filter = Control.MOUSE_FILTER_IGNORE
	frame.add_child(rect)
	return frame


# Vertical fade over artwork so text on top stays readable.
static func shade(strength := 0.85, from_left := false) -> TextureRect:
	var gradient := Gradient.new()
	gradient.set_color(0, Color(BG, strength))
	gradient.set_color(1, Color(BG, 0.0))
	var texture := GradientTexture2D.new()
	texture.gradient = gradient
	if from_left:
		texture.fill_from = Vector2(0, 0.5)
		texture.fill_to = Vector2(0.75, 0.5)
	else:
		texture.fill_from = Vector2(0.5, 1.0)
		texture.fill_to = Vector2(0.5, 0.35)
	var rect := TextureRect.new()
	rect.texture = texture
	rect.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	rect.stretch_mode = TextureRect.STRETCH_SCALE
	rect.mouse_filter = Control.MOUSE_FILTER_IGNORE
	return rect


static func avatar(name: String, size := 40.0, presence := "", ring := Color.TRANSPARENT) -> Control:
	var holder := Control.new()
	holder.custom_minimum_size = Vector2(size, size)
	holder.mouse_filter = Control.MOUSE_FILTER_IGNORE
	var circle := Label.new()
	circle.set_anchors_preset(Control.PRESET_FULL_RECT)
	circle.text = name.strip_edges().left(1).to_upper() if not name.strip_edges().is_empty() else "P"
	circle.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	circle.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	circle.add_theme_font_size_override("font_size", int(size * 0.42))
	circle.add_theme_color_override("font_color", Color("dff4ff"))
	var hue := float(hash(name) % 360) / 360.0
	var fill := Color.from_hsv(hue, 0.45, 0.42)
	var style := box(fill, int(size / 2.0), ring, 2 if ring.a > 0 else 0)
	circle.add_theme_stylebox_override("normal", style)
	holder.add_child(circle)
	if not presence.is_empty():
		var dot_size := maxf(9.0, size * 0.26)
		var dot := Panel.new()
		dot.mouse_filter = Control.MOUSE_FILTER_IGNORE
		dot.set_anchors_preset(Control.PRESET_BOTTOM_RIGHT)
		dot.offset_left = -dot_size
		dot.offset_top = -dot_size
		dot.add_theme_stylebox_override("panel", box(presence_color(presence), int(dot_size / 2.0), BG, 2))
		holder.add_child(dot)
	return holder


static func progress(value: float, color := ACCENT, height := 5.0) -> ProgressBar:
	var bar := ProgressBar.new()
	bar.show_percentage = false
	bar.min_value = 0.0
	bar.max_value = 1.0
	bar.value = clampf(value, 0.0, 1.0)
	bar.custom_minimum_size.y = height
	bar.add_theme_stylebox_override("background", box(Color(1, 1, 1, 0.08), int(height)))
	bar.add_theme_stylebox_override("fill", box(color, int(height)))
	return bar


# Title row used at the top of cards: "Başlık ............ Tümünü Gör →"
static func section_header(title: String, link_text := "", title_size := 15) -> HBoxContainer:
	var row := hbox(8)
	row.add_child(expand(label(title, title_size, TEXT, true)))
	if not link_text.is_empty():
		var link := button(link_text, "link", 12, 24)
		link.name = "Link"
		row.add_child(link)
	return row


static func empty_state(icon: String, title: String, body := "") -> VBoxContainer:
	var column := vbox(6)
	column.alignment = BoxContainer.ALIGNMENT_CENTER
	column.size_flags_vertical = Control.SIZE_EXPAND_FILL
	var glyph := label(icon, 26, TEXT_3)
	glyph.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	column.add_child(glyph)
	var heading := label(title, 14, TEXT_2)
	heading.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	column.add_child(heading)
	if not body.is_empty():
		var detail := label(body, 12, TEXT_3)
		detail.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		detail.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		column.add_child(detail)
	return column


static func clear(node: Node) -> void:
	for child in node.get_children():
		node.remove_child(child)
		child.queue_free()


static func presence_label(presence: String) -> String:
	match presence:
		"in_game": return "Oyunda"
		"busy": return "Meşgul"
		"away": return "Uzakta"
		"online": return "Çevrimiçi"
		_: return "Çevrimdışı"


static func presence_color(presence: String) -> Color:
	match presence:
		"in_game": return CYAN
		"busy": return RED
		"away": return AMBER
		"online": return GREEN
		_: return TEXT_3
