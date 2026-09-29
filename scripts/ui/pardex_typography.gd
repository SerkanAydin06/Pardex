extends Node

# PARDEX-wide typography pass.
# Keeps text readable on 1366x768 laptops while preserving hierarchy on larger screens.

const RETRY_SECONDS := 0.20
const BODY_SIZE := 16
const BUTTON_SIZE := 16
const INPUT_SIZE := 16
const SECTION_TITLE_SIZE := 22
const PAGE_TITLE_SIZE := 36
const PAGE_SUBTITLE_SIZE := 16
const SMALL_SIZE := 14

var _bound := false

func _ready() -> void:
	var tree := get_tree()
	if tree != null and not tree.node_added.is_connected(_on_node_added):
		tree.node_added.connect(_on_node_added)
	call_deferred("_bind")

func _bind() -> void:
	if _bound:
		return
	var tree := get_tree()
	if tree == null:
		return
	var scene := tree.current_scene
	if scene == null or scene.name != "Pardex":
		tree.create_timer(RETRY_SECONDS).timeout.connect(_bind)
		return
	_bound = true
	_style_subtree(scene)

func _on_node_added(node: Node) -> void:
	if not _bound:
		return
	if node is Control:
		call_deferred("_style_subtree", node)

func _style_subtree(node: Node) -> void:
	if node == null or not is_instance_valid(node):
		return
	_style_node(node)
	for child in node.get_children():
		_style_subtree(child)

func _style_node(node: Node) -> void:
	if not (node is Control):
		return
	var control := node as Control
	if _is_window_chrome(control):
		return
	if control is CheckButton:
		_style_check_button(control as CheckButton)
	elif control is Button:
		_style_button(control as Button)
	elif control is LineEdit:
		_style_line_edit(control as LineEdit)
	elif control is RichTextLabel:
		_style_rich_text(control as RichTextLabel)
	elif control is Label:
		_style_label(control as Label)

func _style_label(label: Label) -> void:
	var label_name := String(label.name)
	var path := String(label.get_path())
	var target_size := BODY_SIZE
	var outline_size := 1

	if label_name == "PageTitle":
		target_size = PAGE_TITLE_SIZE
		outline_size = 2
	elif label_name == "PageSubtitle":
		target_size = PAGE_SUBTITLE_SIZE
	elif label_name == "Title":
		target_size = 36 if "HomeHero" in path else SECTION_TITLE_SIZE
		outline_size = 2
	elif label_name.begins_with("Brand"):
		target_size = maxi(28, label.get_theme_font_size("font_size"))
		outline_size = 2
	elif label_name == "Tag":
		target_size = 13
	elif label_name in ["UserName"]:
		target_size = 17
	elif label_name in ["OnlineState", "ConnectionLabel", "State", "Status", "More"]:
		target_size = SMALL_SIZE
	else:
		target_size = maxi(BODY_SIZE, label.get_theme_font_size("font_size"))

	label.add_theme_font_size_override("font_size", target_size)
	label.add_theme_color_override("font_outline_color", Color(0.0, 0.018, 0.035, 0.82))
	label.add_theme_constant_override("outline_size", outline_size)

	if target_size >= SECTION_TITLE_SIZE:
		label.add_theme_color_override("font_shadow_color", Color(0.0, 0.0, 0.0, 0.46))
		label.add_theme_constant_override("shadow_offset_x", 0)
		label.add_theme_constant_override("shadow_offset_y", 2)
		label.add_theme_constant_override("shadow_outline_size", 2)

func _style_button(button: Button) -> void:
	var button_name := String(button.name)
	if button_name in ["MinimizeButton", "MaximizeButton", "CloseButton", "SecondaryAction"]:
		return
	var target_size := BUTTON_SIZE
	if button_name in ["HomeButton", "LibraryButton", "FriendsButton", "RoomsButton", "SettingsButton", "ExitButton"]:
		target_size = 17
		button.custom_minimum_size.y = maxf(button.custom_minimum_size.y, 56.0)
	else:
		button.custom_minimum_size.y = maxf(button.custom_minimum_size.y, 46.0)
	button.add_theme_font_size_override("font_size", target_size)
	button.add_theme_color_override("font_outline_color", Color(0.0, 0.018, 0.035, 0.88))
	button.add_theme_constant_override("outline_size", 1)

func _style_line_edit(edit: LineEdit) -> void:
	edit.add_theme_font_size_override("font_size", INPUT_SIZE)
	edit.custom_minimum_size.y = maxf(edit.custom_minimum_size.y, 46.0)
	edit.add_theme_color_override("font_outline_color", Color(0.0, 0.018, 0.035, 0.72))
	edit.add_theme_constant_override("outline_size", 1)

func _style_check_button(toggle: CheckButton) -> void:
	toggle.add_theme_font_size_override("font_size", BUTTON_SIZE)
	toggle.custom_minimum_size.y = maxf(toggle.custom_minimum_size.y, 44.0)
	toggle.add_theme_color_override("font_outline_color", Color(0.0, 0.018, 0.035, 0.72))
	toggle.add_theme_constant_override("outline_size", 1)

func _style_rich_text(text: RichTextLabel) -> void:
	text.add_theme_font_size_override("normal_font_size", BODY_SIZE)
	text.add_theme_font_size_override("bold_font_size", 18)
	text.add_theme_font_size_override("italics_font_size", BODY_SIZE)
	text.add_theme_font_size_override("bold_italics_font_size", 18)

func _is_window_chrome(control: Control) -> bool:
	var path := String(control.get_path())
	return "WindowChrome" in path
