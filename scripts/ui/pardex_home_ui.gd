extends Node

const RETRY_SECONDS := 0.20
const HOME_SCENE := preload("res://scenes/screens/home_static.tscn")

var _main: Control
var _main_vbox: VBoxContainer
var _header: Control
var _header_text: Control
var _search: LineEdit
var _connection_pill: Control
var _library_button: Button
var _friends_button: Button
var _rooms_button: Button
var _settings_button: Button
var _exit_button: Button
var _home_button: Button
var _home_content: VBoxContainer
var _selected_style: StyleBox
var _normal_style: StyleBox
var _bound := false

func _ready() -> void:
	call_deferred("_bind_ui")

func _bind_ui() -> void:
	if _bound:
		return
	var tree := get_tree()
	if tree == null:
		return
	var scene := tree.current_scene
	if scene == null or scene.name != "Pardex":
		_retry_bind()
		return
	_main = scene as Control
	_main_vbox = _main.get_node_or_null("MainMargin/MainVBox") as VBoxContainer
	_header = _main.get_node_or_null("MainMargin/MainVBox/Header") as Control
	_header_text = _main.get_node_or_null("MainMargin/MainVBox/Header/HeaderRow/HeaderText") as Control
	_search = _main.get_node_or_null("MainMargin/MainVBox/Header/HeaderRow/LibrarySearch") as LineEdit
	_connection_pill = _main.get_node_or_null("MainMargin/MainVBox/Header/HeaderRow/ConnectionPill") as Control
	_library_button = _main.get_node_or_null("Sidebar/SidebarMargin/SidebarVBox/LibraryButton") as Button
	_friends_button = _main.get_node_or_null("Sidebar/SidebarMargin/SidebarVBox/FriendsButton") as Button
	_rooms_button = _main.get_node_or_null("Sidebar/SidebarMargin/SidebarVBox/RoomsButton") as Button
	_settings_button = _main.get_node_or_null("Sidebar/SidebarMargin/SidebarVBox/SettingsButton") as Button
	_exit_button = _main.get_node_or_null("Sidebar/SidebarMargin/SidebarVBox/ExitButton") as Button
	if _main_vbox == null or _header == null or _search == null or _library_button == null or _friends_button == null:
		_retry_bind()
		return
	_selected_style = _library_button.get_theme_stylebox("normal")
	_normal_style = _friends_button.get_theme_stylebox("normal")
	_create_home_button()
	_create_home_content()
	_wire_navigation()
	_bound = true
	_show_home()

func _retry_bind() -> void:
	var tree := get_tree()
	if tree == null:
		return
	tree.create_timer(RETRY_SECONDS).timeout.connect(_bind_ui)

func _create_home_button() -> void:
	var sidebar := _library_button.get_parent()
	_home_button = Button.new()
	_home_button.name = "HomeButton"
	_home_button.text = "⌂  Ana Sayfa"
	_home_button.alignment = HORIZONTAL_ALIGNMENT_LEFT
	_home_button.focus_mode = Control.FOCUS_NONE
	_home_button.add_theme_font_size_override("font_size", 15)
	_home_button.add_theme_color_override("font_color", Color(0.96,0.985,1,1))
	_home_button.add_theme_stylebox_override("normal", _selected_style)
	_home_button.add_theme_stylebox_override("hover", _selected_style)
	sidebar.add_child(_home_button)
	sidebar.move_child(_home_button, _library_button.get_index())

func _create_home_content() -> void:
	_home_content = HOME_SCENE.instantiate() as VBoxContainer
	_home_content.name = "HomeContent"
	_main_vbox.add_child(_home_content)
	_main_vbox.move_child(_home_content, _header.get_index() + 1)
	var library_action := _home_content.get_node_or_null("TopRow/HomeHero/Content/VBox/LibraryAction") as Button
	if library_action != null:
		library_action.pressed.connect(func(): _library_button.emit_signal("pressed"))

func _wire_navigation() -> void:
	_home_button.pressed.connect(_show_home)
	for button in [_library_button, _friends_button, _rooms_button, _settings_button, _exit_button]:
		if button != null:
			button.pressed.connect(_leave_home)

func _show_home() -> void:
	if not _bound:
		return
	for child in _main_vbox.get_children():
		if child is Control:
			(child as Control).visible = (child == _header or child == _home_content)
	if _header_text != null:
		_header_text.hide()
	if _connection_pill != null:
		_connection_pill.hide()
	_search.show()
	_search.placeholder_text = "Oyun, arkadaş veya içerik ara..."
	_search.clear()
	for button in [_library_button, _friends_button, _rooms_button, _settings_button]:
		if button != null:
			button.add_theme_stylebox_override("normal", _normal_style)
	_home_button.add_theme_stylebox_override("normal", _selected_style)

func _leave_home() -> void:
	if not _bound or _home_content == null:
		return
	_home_content.hide()
	if _header_text != null:
		_header_text.show()
	if _connection_pill != null:
		_connection_pill.show()
	_home_button.add_theme_stylebox_override("normal", _normal_style)
