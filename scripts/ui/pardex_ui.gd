extends RefCounted

# PARDEX visual language: colors, panel/button styles and widget factories
# shared by the shell and every page, matching the reference design (deep navy
# glass panels, cyan accent, gold highlights, outline icons).

const Icons := preload("res://scripts/ui/pardex_icons.gd")
const ButtonContent := preload("res://scripts/ui/pardex_button_content.gd")

const BG := Color("060a14")
const SIDEBAR := Color("080d1a")
const SURFACE := Color("0c1424")
const SURFACE_2 := Color("111b30")
const GLASS := Color(0.05, 0.08, 0.15, 0.78)
const BORDER := Color("1a2944")
const BORDER_HI := Color("2b4a78")
const ACCENT := Color("27a9ff")
const ACCENT_2 := Color("1686e0")
const ACCENT_DARK := Color("0d4f8f")
const GOLD := Color("f5b93c")
const TEXT := Color("eef3fb")
const TEXT_2 := Color("a3b1c8")
const TEXT_3 := Color("6b7990")
const GREEN := Color("35d07a")
const AMBER := Color("f3b644")
const RED := Color("ff5d5d")
const CYAN := Color("5fd0ff")
const PURPLE := Color("b06bff")


# ------------------------------------------------------------------ styles

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


static func card_style(pad := 14, radius := 12) -> StyleBoxFlat:
	var style := box(Color(SURFACE, 0.92), radius, BORDER, 1, pad)
	return style


static func glow_style(pad := 0, radius := 12, color := ACCENT) -> StyleBoxFlat:
	var style := box(Color(SURFACE, 0.95), radius, Color(color, 0.55), 1, pad)
	style.shadow_color = Color(color, 0.18)
	style.shadow_size = 10
	return style


# ------------------------------------------------------------------ theme

# App-wide defaults: thin rounded scrollbars, readable base text, and the
# same inputs/buttons the pages use, so older scene screens match too.
static func app_theme() -> Theme:
	var theme := Theme.new()
	theme.default_font_size = 14
	for bar in ["VScrollBar", "HScrollBar"]:
		var track := box(Color(1, 1, 1, 0.03), 4)
		track.set_content_margin_all(2)
		theme.set_stylebox("scroll", bar, track)
		theme.set_stylebox("scroll_focus", bar, track)
		theme.set_stylebox("grabber", bar, box(Color(BORDER_HI, 0.9), 4))
		theme.set_stylebox("grabber_highlight", bar, box(ACCENT_DARK, 4))
		theme.set_stylebox("grabber_pressed", bar, box(ACCENT_2, 4))
	var field := box(Color(SURFACE, 0.95), 10, BORDER, 1, 0)
	field.content_margin_left = 14
	field.content_margin_right = 14
	var field_focus := field.duplicate() as StyleBoxFlat
	field_focus.border_color = ACCENT_2
	theme.set_stylebox("normal", "LineEdit", field)
	theme.set_stylebox("focus", "LineEdit", field_focus)
	theme.set_stylebox("read_only", "LineEdit", field)
	theme.set_color("font_color", "LineEdit", TEXT)
	theme.set_color("font_placeholder_color", "LineEdit", TEXT_3)
	theme.set_font_size("font_size", "LineEdit", 14)
	var popup := box(SURFACE_2, 10, BORDER_HI, 1, 6)
	theme.set_stylebox("panel", "PopupMenu", popup)
	theme.set_stylebox("hover", "PopupMenu", box(Color(ACCENT, 0.18), 6))
	theme.set_color("font_color", "PopupMenu", TEXT)
	theme.set_color("font_hover_color", "PopupMenu", TEXT)
	theme.set_font_size("font_size", "PopupMenu", 14)
	theme.set_stylebox("panel", "PopupPanel", popup)
	theme.set_stylebox("panel", "AcceptDialog", box(SURFACE, 12, BORDER_HI, 1, 16))
	theme.set_stylebox("embedded_border", "Window", box(SURFACE, 12, BORDER_HI, 1, 0))
	theme.set_color("title_color", "Window", TEXT)
	return theme


# Restyle a scene-built screen (Ayarlar) to the shared card/button language.
static func restyle_screen(node: Node) -> void:
	for child in node.get_children():
		if child is PanelContainer and not (child.get_parent() is PanelContainer):
			(child as PanelContainer).add_theme_stylebox_override("panel", card_style(20, 14))
		elif child is CheckButton:
			pass
		elif child is Button:
			var source := child as Button
			var kind := "primary" if not source.disabled else "ghost"
			var styled := button(source.text, kind, 13, 42)
			for state in ["normal", "hover", "pressed", "disabled"]:
				source.add_theme_stylebox_override(state, styled.get_theme_stylebox(state))
			for color_name in ["font_color", "font_hover_color", "font_pressed_color", "font_disabled_color"]:
				source.add_theme_color_override(color_name, styled.get_theme_color(color_name))
			source.add_theme_font_size_override("font_size", 13)
			source.custom_minimum_size.y = maxf(source.custom_minimum_size.y, 42.0)
			source.mouse_default_cursor_shape = Control.CURSOR_POINTING_HAND
			styled.free()
		elif child is LineEdit:
			var edit := child as LineEdit
			for state in ["normal", "focus", "read_only"]:
				edit.remove_theme_stylebox_override(state)
			edit.custom_minimum_size.y = maxf(edit.custom_minimum_size.y, 42.0)
		restyle_screen(child)


# ------------------------------------------------------------------ layout

static func panel(pad := 14, style: StyleBox = null) -> PanelContainer:
	var container := PanelContainer.new()
	container.add_theme_stylebox_override("panel", style if style != null else card_style(pad))
	return container


static func vbox(separation := 8) -> VBoxContainer:
	var container := VBoxContainer.new()
	container.add_theme_constant_override("separation", separation)
	return container


static func hbox(separation := 8) -> HBoxContainer:
	var container := HBoxContainer.new()
	container.add_theme_constant_override("separation", separation)
	return container


static func margin(child: Control, left := 0, top := 0, right := 0, bottom := 0) -> MarginContainer:
	var container := MarginContainer.new()
	container.add_theme_constant_override("margin_left", left)
	container.add_theme_constant_override("margin_top", top)
	container.add_theme_constant_override("margin_right", right)
	container.add_theme_constant_override("margin_bottom", bottom)
	container.add_child(child)
	return container


static func spacer() -> Control:
	var item := Control.new()
	item.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	item.mouse_filter = Control.MOUSE_FILTER_IGNORE
	return item


static func vspacer() -> Control:
	var item := Control.new()
	item.size_flags_vertical = Control.SIZE_EXPAND_FILL
	item.mouse_filter = Control.MOUSE_FILTER_IGNORE
	return item


static func expand(control: Control, ratio := 1.0) -> Control:
	control.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	control.size_flags_stretch_ratio = ratio
	return control


static func scroll_page(child: Control) -> ScrollContainer:
	var scroll := ScrollContainer.new()
	scroll.size_flags_vertical = Control.SIZE_EXPAND_FILL
	scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	child.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	scroll.add_child(child)
	return scroll


static func divider() -> ColorRect:
	var line := ColorRect.new()
	line.color = BORDER
	line.custom_minimum_size.y = 1
	line.mouse_filter = Control.MOUSE_FILTER_IGNORE
	return line


# Gives a node a scene-unique name (%Name) so page scripts can find it in their
# .tscn scene.
static func named(node: Node, unique: String) -> Node:
	node.name = unique
	node.unique_name_in_owner = true
	return node


# Makes `root` the owner of every node below it so the tree can be packed into
# a scene (popups, dialogs and timers stay runtime-only).
static func own(root: Node, node: Node = null) -> void:
	for child in (root if node == null else node).get_children():
		if child is Window or child is Timer:
			continue
		child.owner = root
		own(root, child)


static func clear(node: Node) -> void:
	for child in node.get_children():
		node.remove_child(child)
		child.queue_free()


# ------------------------------------------------------------------ text

static func label(text: String, size := 14, color := TEXT, bold := false) -> Label:
	var item := Label.new()
	item.text = text
	item.add_theme_font_size_override("font_size", size)
	item.add_theme_color_override("font_color", color)
	if bold:
		item.add_theme_constant_override("outline_size", 1 if size < 22 else 2)
		item.add_theme_color_override("font_outline_color", color)
	return item


# Single-line text that may be cut with "…". Only for labels whose parent
# chain hands them the row's full width.
static func fit(item: Label) -> Label:
	item.text_overrun_behavior = TextServer.OVERRUN_TRIM_ELLIPSIS
	item.clip_text = true
	return item


static func wrapped(item: Label) -> Label:
	item.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	return item


# ------------------------------------------------------------------ icons

static func icon(name: String, size := 20, color := TEXT) -> TextureRect:
	var rect := TextureRect.new()
	rect.texture = Icons.texture(name, size * 2)
	rect.custom_minimum_size = Vector2(size, size)
	rect.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	rect.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	rect.texture_filter = CanvasItem.TEXTURE_FILTER_LINEAR
	rect.modulate = color
	rect.mouse_filter = Control.MOUSE_FILTER_IGNORE
	rect.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	return rect


# Rounded square holding an icon, like the stat and list tiles in the design.
static func icon_tile(name: String, size := 44, color := ACCENT, bg := SURFACE_2) -> PanelContainer:
	var tile := panel(0, box(bg, 10, BORDER, 1))
	tile.custom_minimum_size = Vector2(size, size)
	tile.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	var center := CenterContainer.new()
	center.add_child(icon(name, int(size * 0.5), color))
	tile.add_child(center)
	return tile


static func _apply_icon(item: Button, icon_name: String, icon_size: int, color: Color) -> void:
	if icon_name.is_empty():
		return
	item.icon = Icons.texture(icon_name, icon_size * 2)
	item.expand_icon = false
	item.add_theme_constant_override("icon_max_width", icon_size)
	item.add_theme_constant_override("h_separation", 8)
	for state in ["icon_normal_color", "icon_hover_color", "icon_pressed_color", "icon_focus_color"]:
		item.add_theme_color_override(state, color)
	item.add_theme_color_override("icon_disabled_color", TEXT_3)


# ------------------------------------------------------------------ buttons

# kind: "primary" (cyan), "gold", "ghost" (dark outline), "link" (text only),
# "success" (green)
static func button(text: String, kind := "primary", font_size := 13, height := 36.0, icon_name := "") -> Button:
	var item := Button.new()
	item.text = text
	item.focus_mode = Control.FOCUS_NONE
	item.mouse_default_cursor_shape = Control.CURSOR_POINTING_HAND
	item.custom_minimum_size.y = height
	item.add_theme_font_size_override("font_size", font_size)
	var bg := ACCENT
	var fg := Color("031423")
	var border := Color(ACCENT.lightened(0.3), 0.8)
	match kind:
		"gold":
			bg = GOLD
			fg = Color("241703")
			border = GOLD.lightened(0.2)
		"success":
			bg = Color(GREEN, 0.22)
			fg = GREEN.lightened(0.2)
			border = Color(GREEN, 0.6)
		"ghost":
			bg = Color(SURFACE_2, 0.85)
			fg = TEXT
			border = BORDER_HI
		"link":
			bg = Color.TRANSPARENT
			fg = ACCENT
			border = Color.TRANSPARENT
	var normal := box(bg, 9, border, 1 if border.a > 0 else 0)
	normal.content_margin_left = 16
	normal.content_margin_right = 16
	if kind == "primary":
		normal.shadow_color = Color(ACCENT, 0.28)
		normal.shadow_size = 8
	var hover := normal.duplicate() as StyleBoxFlat
	hover.bg_color = bg.lightened(0.1) if kind != "link" else Color(1, 1, 1, 0.04)
	if kind == "ghost":
		hover.border_color = ACCENT
	var disabled := normal.duplicate() as StyleBoxFlat
	disabled.bg_color = Color(1, 1, 1, 0.05) if kind != "link" else Color.TRANSPARENT
	disabled.border_color = BORDER
	disabled.shadow_size = 0
	item.add_theme_stylebox_override("normal", normal)
	item.add_theme_stylebox_override("hover", hover)
	item.add_theme_stylebox_override("pressed", hover)
	item.add_theme_stylebox_override("disabled", disabled)
	item.add_theme_color_override("font_color", fg)
	item.add_theme_color_override("font_hover_color", fg)
	item.add_theme_color_override("font_pressed_color", fg)
	item.add_theme_color_override("font_disabled_color", TEXT_3)
	if icon_name.is_empty() or kind == "link":
		_apply_icon(item, icon_name, 16 if font_size < 15 else 18, fg)
	else:
		_center_icon_and_text(item, icon_name, 16 if font_size < 15 else 18, fg, font_size)
	return item


# Icon + label as one centered group. A native Button pins its icon to the
# left edge while the text centers, which leaves the icon stranded on wide
# buttons ("Profili Düzenle", "Arkadaş Ekle" ...).
static func _center_icon_and_text(item: Button, icon_name: String, icon_size: int, fg: Color, font_size: int) -> void:
	var caption := item.text
	item.text = ""
	item.set_meta("label", caption)
	var center := CenterContainer.new()
	center.set_script(ButtonContent)
	center.set("color", fg)
	center.set("disabled_color", TEXT_3)
	center.name = "Content"
	center.set_anchors_preset(Control.PRESET_FULL_RECT)
	center.mouse_filter = Control.MOUSE_FILTER_IGNORE
	var group := hbox(9)
	group.name = "Group"
	group.mouse_filter = Control.MOUSE_FILTER_IGNORE
	var glyph := icon(icon_name, icon_size, fg)
	glyph.name = "Icon"
	group.add_child(glyph)
	var text := label(caption, font_size, fg)
	text.name = "Label"
	text.mouse_filter = Control.MOUSE_FILTER_IGNORE
	group.add_child(text)
	center.add_child(group)
	item.add_child(center)
	var font := ThemeDB.fallback_font
	var text_width := font.get_string_size(caption, HORIZONTAL_ALIGNMENT_LEFT, -1, font_size).x
	item.custom_minimum_size.x = maxf(item.custom_minimum_size.x, ceilf(text_width) + icon_size + 9 + 34)


static func link(text: String, font_size := 13) -> Button:
	var item := button(text + "  ", "link", font_size, 24)
	item.icon = Icons.texture("arrow_right", 28)
	item.icon_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	item.add_theme_constant_override("icon_max_width", 14)
	for state in ["icon_normal_color", "icon_hover_color", "icon_pressed_color"]:
		item.add_theme_color_override(state, ACCENT)
	var flat := box(Color.TRANSPARENT, 6)
	for state in ["normal", "hover", "pressed"]:
		item.add_theme_stylebox_override(state, flat)
	return item


static func icon_button(icon_name: String, tooltip := "", size := 36.0, color := TEXT_2, framed := false) -> Button:
	var item := Button.new()
	item.tooltip_text = tooltip
	item.focus_mode = Control.FOCUS_NONE
	item.mouse_default_cursor_shape = Control.CURSOR_POINTING_HAND
	item.custom_minimum_size = Vector2(size, size)
	item.icon = Icons.texture(icon_name, int(size))
	item.icon_alignment = HORIZONTAL_ALIGNMENT_CENTER
	item.expand_icon = false
	item.add_theme_constant_override("icon_max_width", int(size * 0.5))
	item.add_theme_color_override("icon_normal_color", color)
	item.add_theme_color_override("icon_hover_color", TEXT)
	item.add_theme_color_override("icon_pressed_color", TEXT)
	item.add_theme_color_override("icon_disabled_color", Color(TEXT_3, 0.6))
	var normal := box(Color(SURFACE_2, 0.9) if framed else Color.TRANSPARENT, 9, BORDER if framed else Color.TRANSPARENT, 1 if framed else 0)
	var hover := box(Color(1, 1, 1, 0.08), 9, BORDER_HI if framed else Color.TRANSPARENT, 1 if framed else 0)
	item.add_theme_stylebox_override("normal", normal)
	item.add_theme_stylebox_override("hover", hover)
	item.add_theme_stylebox_override("pressed", hover)
	item.add_theme_stylebox_override("disabled", normal)
	return item


# Segmented filter tab (Tümü / Yüklü / ...), optionally with an icon.
static func segment(text: String, icon_name := "", active := false) -> Button:
	var item := Button.new()
	item.text = text
	item.toggle_mode = true
	item.button_pressed = active
	item.focus_mode = Control.FOCUS_NONE
	item.mouse_default_cursor_shape = Control.CURSOR_POINTING_HAND
	item.custom_minimum_size.y = 42
	item.add_theme_font_size_override("font_size", 13)
	var normal := box(Color(SURFACE, 0.9), 8, BORDER, 1)
	normal.content_margin_left = 18
	normal.content_margin_right = 18
	var on := box(ACCENT, 8, ACCENT.lightened(0.3), 1)
	on.content_margin_left = 18
	on.content_margin_right = 18
	on.shadow_color = Color(ACCENT, 0.3)
	on.shadow_size = 8
	var hover := normal.duplicate() as StyleBoxFlat
	hover.border_color = BORDER_HI
	item.add_theme_stylebox_override("normal", normal)
	item.add_theme_stylebox_override("hover", hover)
	item.add_theme_stylebox_override("pressed", on)
	item.add_theme_stylebox_override("hover_pressed", on)
	item.add_theme_color_override("font_color", TEXT_2)
	item.add_theme_color_override("font_hover_color", TEXT)
	item.add_theme_color_override("font_pressed_color", Color("031423"))
	item.add_theme_color_override("font_hover_pressed_color", Color("031423"))
	if not icon_name.is_empty():
		_apply_icon(item, icon_name, 16, TEXT_2)
		item.add_theme_color_override("icon_pressed_color", Color("031423"))
	return item


# Small colored pill: "Yüklü", "Yeni", "Popüler", "Aktif"...
static func pill(text: String, color := ACCENT, icon_name := "", font_size := 11, solid := false) -> PanelContainer:
	var style := box(color if solid else Color(color, 0.18), 12, Color(color, 0.7), 1)
	style.content_margin_left = 9
	style.content_margin_right = 10
	style.content_margin_top = 3
	style.content_margin_bottom = 3
	var holder := panel(0, style)
	holder.size_flags_horizontal = Control.SIZE_SHRINK_BEGIN
	holder.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	holder.mouse_filter = Control.MOUSE_FILTER_IGNORE
	var row := hbox(5)
	holder.add_child(row)
	var fg := Color("06121f") if solid else color.lightened(0.35)
	if not icon_name.is_empty():
		row.add_child(icon(icon_name, font_size + 2, fg))
	row.add_child(label(text, font_size, fg, solid))
	return holder


static func search_field(placeholder: String, height := 40.0) -> LineEdit:
	var field := LineEdit.new()
	field.placeholder_text = placeholder
	field.custom_minimum_size.y = height
	field.clear_button_enabled = true
	field.add_theme_font_size_override("font_size", 13)
	field.add_theme_color_override("font_color", TEXT)
	field.add_theme_color_override("font_placeholder_color", TEXT_3)
	var normal := box(Color(SURFACE, 0.9), 10, BORDER, 1)
	normal.content_margin_left = 40
	normal.content_margin_right = 10
	var focus := normal.duplicate() as StyleBoxFlat
	focus.border_color = ACCENT_2
	field.add_theme_stylebox_override("normal", normal)
	field.add_theme_stylebox_override("focus", focus)
	field.add_theme_stylebox_override("read_only", normal)
	var glass := icon("search", 18, TEXT_2)
	glass.set_anchors_preset(Control.PRESET_CENTER_LEFT)
	glass.offset_left = 14
	glass.offset_top = -9
	glass.offset_right = 32
	glass.offset_bottom = 9
	field.add_child(glass)
	return field


# ------------------------------------------------------------------ media

# Rounded image that fills its box, cropping to cover.
static func image(texture: Texture2D, min_size := Vector2.ZERO, radius := 10) -> PanelContainer:
	var frame := PanelContainer.new()
	frame.clip_children = CanvasItem.CLIP_CHILDREN_AND_DRAW
	frame.custom_minimum_size = min_size
	frame.add_theme_stylebox_override("panel", box(SURFACE_2, radius))
	var rect := TextureRect.new()
	rect.name = "Art"
	rect.texture = texture
	rect.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	rect.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_COVERED
	rect.texture_filter = CanvasItem.TEXTURE_FILTER_LINEAR_WITH_MIPMAPS
	rect.mouse_filter = Control.MOUSE_FILTER_IGNORE
	frame.add_child(rect)
	return frame


# Fade over artwork so text on top stays readable.
static func shade(strength := 0.85, from_left := false, color := BG) -> TextureRect:
	var gradient := Gradient.new()
	gradient.set_color(0, Color(color, strength))
	gradient.set_color(1, Color(color, 0.0))
	var texture := GradientTexture2D.new()
	texture.gradient = gradient
	if from_left:
		texture.fill_from = Vector2(0, 0.5)
		texture.fill_to = Vector2(0.72, 0.5)
	else:
		texture.fill_from = Vector2(0.5, 1.0)
		texture.fill_to = Vector2(0.5, 0.3)
	var rect := TextureRect.new()
	rect.texture = texture
	rect.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	rect.stretch_mode = TextureRect.STRETCH_SCALE
	rect.mouse_filter = Control.MOUSE_FILTER_IGNORE
	return rect


static func avatar(name: String, size := 40.0, presence := "", ring := Color.TRANSPARENT) -> Control:
	var holder := Control.new()
	holder.custom_minimum_size = Vector2(size, size)
	holder.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	holder.mouse_filter = Control.MOUSE_FILTER_IGNORE
	var circle := Label.new()
	circle.set_anchors_preset(Control.PRESET_FULL_RECT)
	var clean := name.strip_edges()
	circle.text = clean.left(1).to_upper() if not clean.is_empty() else "P"
	circle.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	circle.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	circle.add_theme_font_size_override("font_size", int(size * 0.42))
	circle.add_theme_color_override("font_color", Color("e8f6ff"))
	var hue := float(absi(hash(clean)) % 360) / 360.0
	var fill := Color.from_hsv(hue, 0.5, 0.45)
	var style := box(fill, int(size / 2.0), ring, maxi(2, int(size / 22.0)) if ring.a > 0 else 0)
	circle.add_theme_stylebox_override("normal", style)
	holder.add_child(circle)
	if not presence.is_empty():
		var dot_size := maxf(10.0, size * 0.27)
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
	bar.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	bar.add_theme_stylebox_override("background", box(Color(1, 1, 1, 0.08), int(height)))
	bar.add_theme_stylebox_override("fill", box(color, int(height)))
	return bar


# ------------------------------------------------------------------ blocks

# "Başlık (3) ............ Tümünü Gör →"
static func section_header(title: String, link_text := "", title_size := 18, icon_name := "", icon_color := ACCENT) -> HBoxContainer:
	var row := hbox(10)
	if not icon_name.is_empty():
		row.add_child(icon(icon_name, title_size + 2, icon_color))
	var heading := label(title, title_size, TEXT, true)
	heading.name = "Title"
	row.add_child(heading)
	var fill := spacer()
	fill.name = "Fill"
	row.add_child(fill)
	if not link_text.is_empty():
		var go := link(link_text, 13)
		go.name = "Link"
		row.add_child(go)
	return row


# Icon tile + big value + caption (profile and library stats).
static func stat_tile(icon_name: String, value: String, caption: String, color := ACCENT) -> PanelContainer:
	var card := panel(0, box(Color(SURFACE, 0.85), 12, BORDER, 1, 10))
	var row := hbox(10)
	card.add_child(row)
	row.add_child(icon_tile(icon_name, 40, color))
	var text := vbox(0)
	text.alignment = BoxContainer.ALIGNMENT_CENTER
	text.add_child(label(value, 22, TEXT, true))
	text.add_child(fit(label(caption, 12, TEXT_2)))
	row.add_child(expand(text))
	return card


static func empty_state(icon_name: String, title: String, body := "", compact := false) -> VBoxContainer:
	var column := vbox(4 if compact else 8)
	column.alignment = BoxContainer.ALIGNMENT_CENTER
	column.size_flags_vertical = Control.SIZE_EXPAND_FILL
	var glyph := CenterContainer.new()
	glyph.add_child(icon(icon_name, 22 if compact else 30, TEXT_3))
	column.add_child(glyph)
	var heading := label(title, 13 if compact else 14, TEXT_2)
	heading.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	column.add_child(heading)
	if not body.is_empty():
		var detail := wrapped(label(body, 12, TEXT_3))
		detail.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		column.add_child(detail)
	return column


static func presence_label(presence: String) -> String:
	match presence:
		"in_game": return "Oyunda"
		"busy": return "Meşgul"
		"away": return "Boşta"
		"online": return "Çevrimiçi"
		_: return "Çevrimdışı"


static func presence_color(presence: String) -> Color:
	match presence:
		"in_game": return GREEN
		"busy": return RED
		"away": return AMBER
		"online": return GREEN
		_: return TEXT_3
