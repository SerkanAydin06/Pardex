extends Node

# Steam-style responsive desktop shell for PARDEX.
# Layout reflows; text/icons stay readable and the home screen fills the viewport.

const DESIGN_SIZE := Vector2i(1440, 900)
const WINDOW_MIN_SIZE := Vector2i(960, 620)
const SCREEN_FILL := 0.96
const BIND_RETRY_SECONDS := 0.20

const WINDOW_NARROW := 1180
const WINDOW_COMPACT := 1400
const CONTENT_STACK_BOTTOM := 980
const CONTENT_STACK_TOP := 760

var _bound := false
var _main: Control
var _sidebar: Control
var _sidebar_margin: MarginContainer
var _main_margin: MarginContainer
var _search: LineEdit
var _library_root: VBoxContainer

var _home_root: VBoxContainer
var _home_scroll: ScrollContainer
var _home_body: VBoxContainer
var _home_top_grid: GridContainer
var _home_bottom_grid: GridContainer
var _recent_grid: GridContainer
var _home_hero: Control
var _home_agenda: Control
var _home_recent: Control
var _home_quick: Control

var _library_scroll: ScrollContainer
var _library_body: VBoxContainer

func _ready() -> void:
	call_deferred("_bind_after_scene_ready")

func _bind_after_scene_ready() -> void:
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
	_sidebar = _main.get_node_or_null("Sidebar") as Control
	_sidebar_margin = _main.get_node_or_null("Sidebar/SidebarMargin") as MarginContainer
	_main_margin = _main.get_node_or_null("MainMargin") as MarginContainer
	_search = _main.get_node_or_null("MainMargin/MainVBox/Header/HeaderRow/LibrarySearch") as LineEdit
	_library_root = _main.get_node_or_null("MainMargin/MainVBox/LibraryContent") as VBoxContainer
	if _sidebar == null or _main_margin == null or _library_root == null:
		_retry_bind()
		return
	_bound = true
	await tree.process_frame
	_apply_for_current_screen()
	await tree.create_timer(0.25).timeout
	if not is_instance_valid(_main):
		return
	_ensure_library_scroll()
	_ensure_home_reflow()
	_apply_responsive_layout()
	get_window().size_changed.connect(_on_window_size_changed)

func _retry_bind() -> void:
	var tree := get_tree()
	if tree == null:
		return
	tree.create_timer(BIND_RETRY_SECONDS).timeout.connect(_bind_after_scene_ready)

func _apply_for_current_screen() -> void:
	var screen := DisplayServer.window_get_current_screen()
	var usable := DisplayServer.screen_get_usable_rect(screen)
	if usable.size.x <= 0 or usable.size.y <= 0:
		return
	get_window().min_size = Vector2i(mini(WINDOW_MIN_SIZE.x, usable.size.x), mini(WINDOW_MIN_SIZE.y, usable.size.y))
	if DisplayServer.window_get_mode() == DisplayServer.WINDOW_MODE_WINDOWED:
		var current := DisplayServer.window_get_size()
		var safe_max := Vector2i(maxi(1, floori(float(usable.size.x) * SCREEN_FILL)), maxi(1, floori(float(usable.size.y) * SCREEN_FILL)))
		var preferred := Vector2i(mini(DESIGN_SIZE.x, safe_max.x), mini(DESIGN_SIZE.y, safe_max.y))
		var target := Vector2i(mini(current.x, preferred.x), mini(current.y, preferred.y))
		target.x = maxi(target.x, mini(WINDOW_MIN_SIZE.x, safe_max.x))
		target.y = maxi(target.y, mini(WINDOW_MIN_SIZE.y, safe_max.y))
		if target != current:
			DisplayServer.window_set_size(target)
			_center_window(usable, target)
	_apply_shell_density()

func _center_window(usable: Rect2i, window_size: Vector2i) -> void:
	var x := usable.position.x + maxi(0, roundi(float(usable.size.x - window_size.x) * 0.5))
	var y := usable.position.y + maxi(0, roundi(float(usable.size.y - window_size.y) * 0.5))
	DisplayServer.window_set_position(Vector2i(x, y))

func _on_window_size_changed() -> void:
	if not _bound or not is_instance_valid(_main):
		return
	call_deferred("_apply_responsive_layout")

func _apply_responsive_layout() -> void:
	_apply_shell_density()
	_ensure_home_reflow()
	_apply_home_reflow()
	_apply_library_density()

func _apply_shell_density() -> void:
	if _sidebar == null or _main_margin == null:
		return
	var window_width := DisplayServer.window_get_size().x
	var narrow := window_width <= WINDOW_NARROW
	var compact := window_width <= WINDOW_COMPACT
	# Reference keeps the navigation substantial even on a 1366-wide laptop.
	var sidebar_width := 220.0 if narrow else (250.0 if compact else 270.0)
	_sidebar.offset_right = sidebar_width
	_main_margin.offset_left = sidebar_width
	var outer_margin := 10 if narrow else (14 if compact else 18)
	_main_margin.add_theme_constant_override("margin_left", outer_margin)
	_main_margin.add_theme_constant_override("margin_top", 10 if narrow else 12)
	_main_margin.add_theme_constant_override("margin_right", outer_margin)
	_main_margin.add_theme_constant_override("margin_bottom", 10 if narrow else 12)
	if _sidebar_margin != null:
		var side_margin := 14 if narrow else (18 if compact else 22)
		_sidebar_margin.add_theme_constant_override("margin_left", side_margin)
		_sidebar_margin.add_theme_constant_override("margin_top", 18 if compact else 24)
		_sidebar_margin.add_theme_constant_override("margin_right", side_margin)
		_sidebar_margin.add_theme_constant_override("margin_bottom", 16 if compact else 22)
	if _search != null:
		var search_width := 260.0 if narrow else (330.0 if compact else 430.0)
		_search.custom_minimum_size = Vector2(search_width, maxf(48.0, _search.custom_minimum_size.y))
	var sidebar_vbox := _main.get_node_or_null("Sidebar/SidebarMargin/SidebarVBox") as VBoxContainer
	if sidebar_vbox != null:
		sidebar_vbox.add_theme_constant_override("separation", 8 if narrow else 10)

func _ensure_home_reflow() -> void:
	if _home_scroll != null and is_instance_valid(_home_scroll):
		return
	_home_root = _main.get_node_or_null("MainMargin/MainVBox/HomeContent") as VBoxContainer
	if _home_root == null or _home_root.get_child_count() < 2:
		return
	var old_top := _home_root.get_child(0) as HBoxContainer
	var old_bottom := _home_root.get_child(1) as HBoxContainer
	if old_top == null or old_bottom == null or old_top.get_child_count() < 2 or old_bottom.get_child_count() < 2:
		return
	_home_hero = old_top.get_child(0) as Control
	_home_agenda = old_top.get_child(1) as Control
	_home_recent = old_bottom.get_child(0) as Control
	_home_quick = old_bottom.get_child(1) as Control
	if _home_hero == null or _home_agenda == null or _home_recent == null or _home_quick == null:
		return
	_home_scroll = ScrollContainer.new()
	_home_scroll.name = "ResponsiveScroll"
	_home_scroll.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_home_scroll.size_flags_vertical = Control.SIZE_EXPAND_FILL
	_home_scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	_home_scroll.vertical_scroll_mode = ScrollContainer.SCROLL_MODE_AUTO
	_home_root.add_child(_home_scroll)
	_home_body = VBoxContainer.new()
	_home_body.name = "ResponsiveBody"
	_home_body.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_home_body.size_flags_vertical = Control.SIZE_EXPAND_FILL
	_home_body.add_theme_constant_override("separation", 14)
	_home_scroll.add_child(_home_body)
	_home_top_grid = GridContainer.new()
	_home_top_grid.name = "TopGrid"
	_home_top_grid.columns = 2
	_home_top_grid.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_home_top_grid.size_flags_vertical = Control.SIZE_EXPAND_FILL
	_home_top_grid.size_flags_stretch_ratio = 1.08
	_home_top_grid.add_theme_constant_override("h_separation", 14)
	_home_top_grid.add_theme_constant_override("v_separation", 14)
	_home_body.add_child(_home_top_grid)
	_home_bottom_grid = GridContainer.new()
	_home_bottom_grid.name = "BottomGrid"
	_home_bottom_grid.columns = 2
	_home_bottom_grid.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_home_bottom_grid.size_flags_vertical = Control.SIZE_EXPAND_FILL
	_home_bottom_grid.size_flags_stretch_ratio = 1.0
	_home_bottom_grid.add_theme_constant_override("h_separation", 14)
	_home_bottom_grid.add_theme_constant_override("v_separation", 14)
	_home_body.add_child(_home_bottom_grid)
	_home_hero.reparent(_home_top_grid, false)
	_home_agenda.reparent(_home_top_grid, false)
	_home_recent.reparent(_home_bottom_grid, false)
	_home_quick.reparent(_home_bottom_grid, false)
	old_top.queue_free()
	old_bottom.queue_free()
	for control in [_home_hero, _home_agenda, _home_recent, _home_quick]:
		control.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		control.size_flags_vertical = Control.SIZE_EXPAND_FILL
	_home_hero.size_flags_stretch_ratio = 2.0
	_home_agenda.size_flags_stretch_ratio = 1.0
	_home_recent.size_flags_stretch_ratio = 2.0
	_home_quick.size_flags_stretch_ratio = 1.0
	_ensure_recent_grid()

func _ensure_recent_grid() -> void:
	if _home_recent == null or not is_instance_valid(_home_recent) or (_recent_grid != null and is_instance_valid(_recent_grid)):
		return
	var recent_box := _home_recent as VBoxContainer
	if recent_box == null or recent_box.get_child_count() < 2:
		return
	var old_cards := recent_box.get_child(1) as HBoxContainer
	if old_cards == null:
		return
	_recent_grid = GridContainer.new()
	_recent_grid.name = "RecentGrid"
	_recent_grid.columns = 4
	_recent_grid.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_recent_grid.size_flags_vertical = Control.SIZE_EXPAND_FILL
	_recent_grid.add_theme_constant_override("h_separation", 10)
	_recent_grid.add_theme_constant_override("v_separation", 10)
	recent_box.add_child(_recent_grid)
	recent_box.move_child(_recent_grid, 1)
	for card in old_cards.get_children():
		if card is Control:
			(card as Control).custom_minimum_size = Vector2(150, 240)
			(card as Control).size_flags_horizontal = Control.SIZE_EXPAND_FILL
			(card as Control).size_flags_vertical = Control.SIZE_EXPAND_FILL
		card.reparent(_recent_grid, false)
	old_cards.queue_free()

func _apply_home_reflow() -> void:
	if _home_root == null or not is_instance_valid(_home_root) or _home_top_grid == null:
		return
	var content_width := _home_root.size.x
	if content_width <= 1.0:
		content_width = maxf(600.0, float(DisplayServer.window_get_size().x) - _sidebar.offset_right - 40.0)
	_home_top_grid.columns = 1 if content_width < CONTENT_STACK_TOP else 2
	_home_bottom_grid.columns = 1 if content_width < CONTENT_STACK_BOTTOM else 2
	var viewport_height := maxf(620.0, _home_scroll.size.y)
	var gap := 14.0
	var top_height := clampf(viewport_height * 0.53, 285.0, 405.0)
	var bottom_height := maxf(300.0, viewport_height - top_height - gap)
	_home_body.custom_minimum_size = Vector2(0, viewport_height)
	_home_top_grid.custom_minimum_size = Vector2(0, top_height)
	_home_bottom_grid.custom_minimum_size = Vector2(0, bottom_height)
	_home_hero.custom_minimum_size = Vector2(0, top_height)
	_home_agenda.custom_minimum_size = Vector2(320 if _home_top_grid.columns == 2 else 0, top_height)
	_home_recent.custom_minimum_size = Vector2(0, bottom_height)
	_home_quick.custom_minimum_size = Vector2(320 if _home_bottom_grid.columns == 2 else 0, bottom_height)
	if _recent_grid != null:
		if content_width >= 900.0:
			_recent_grid.columns = 4
		elif content_width >= 650.0:
			_recent_grid.columns = 3
		else:
			_recent_grid.columns = 2
		for card in _recent_grid.get_children():
			if card is Control:
				(card as Control).custom_minimum_size.y = maxf(240.0, bottom_height - 42.0)
				var art := card.get_node_or_null("VBox/Artwork") as Control
				if art != null:
					art.size_flags_vertical = Control.SIZE_EXPAND_FILL
	if _home_quick != null:
		var quick_box := _home_quick.get_node_or_null("VBox") as VBoxContainer
		if quick_box != null:
			for child in quick_box.get_children():
				if child is HBoxContainer:
					(child as HBoxContainer).size_flags_vertical = Control.SIZE_EXPAND_FILL
	var compact := content_width < CONTENT_STACK_BOTTOM
	var separation := 10 if compact else 14
	_home_body.add_theme_constant_override("separation", separation)
	_home_top_grid.add_theme_constant_override("h_separation", separation)
	_home_top_grid.add_theme_constant_override("v_separation", separation)
	_home_bottom_grid.add_theme_constant_override("h_separation", separation)
	_home_bottom_grid.add_theme_constant_override("v_separation", separation)

func _ensure_library_scroll() -> void:
	if _library_scroll != null and is_instance_valid(_library_scroll):
		return
	if _library_root == null:
		return
	var original_children := _library_root.get_children()
	if original_children.is_empty():
		return
	_library_scroll = ScrollContainer.new()
	_library_scroll.name = "ResponsiveScroll"
	_library_scroll.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_library_scroll.size_flags_vertical = Control.SIZE_EXPAND_FILL
	_library_scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	_library_scroll.vertical_scroll_mode = ScrollContainer.SCROLL_MODE_AUTO
	_library_root.add_child(_library_scroll)
	_library_body = VBoxContainer.new()
	_library_body.name = "ResponsiveBody"
	_library_body.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_library_body.add_theme_constant_override("separation", 18)
	_library_scroll.add_child(_library_body)
	for child in original_children:
		child.reparent(_library_body, false)

func _apply_library_density() -> void:
	if _library_body == null or not is_instance_valid(_library_body):
		return
	var width := _library_root.size.x
	var compact := width < 1000.0
	_library_body.add_theme_constant_override("separation", 12 if compact else 18)
	var hero := _library_body.get_node_or_null("Hero") as Control
	if hero != null:
		hero.custom_minimum_size = Vector2(0, 205 if compact else 244)
