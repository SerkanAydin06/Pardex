extends Node

# PARDEX responsive window/layout controller.
# Keeps the 1440x900 design as the preferred desktop size, but constrains the
# real window to the active monitor and applies a compact layout on laptop-class
# displays (1366x768, 1280x720, etc.).

const DESIGN_SIZE := Vector2i(1440, 900)
const COMPACT_BREAKPOINT := Vector2i(1400, 820)
const COMPACT_MIN_SIZE := Vector2i(960, 620)
const SCREEN_FILL := 0.96
const BIND_RETRY_SECONDS := 0.20

var _bound := false
var _main: Control
var _sidebar: Control
var _main_margin: MarginContainer
var _search: LineEdit


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
	_main_margin = _main.get_node_or_null("MainMargin") as MarginContainer
	_search = _main.get_node_or_null("MainMargin/MainVBox/Header/HeaderRow/LibrarySearch") as LineEdit
	if _sidebar == null or _main_margin == null:
		_retry_bind()
		return

	_bound = true
	# main.gd restores saved window state during scene _ready(). Waiting one frame
	# makes this controller the final authority for monitor fitting.
	await tree.process_frame
	_apply_for_current_screen()
	get_window().size_changed.connect(_on_window_size_changed)


func _retry_bind() -> void:
	var tree := get_tree()
	if tree == null:
		return
	var timer := tree.create_timer(BIND_RETRY_SECONDS)
	timer.timeout.connect(_bind_after_scene_ready)


func _apply_for_current_screen() -> void:
	var screen := DisplayServer.window_get_current_screen()
	var usable := DisplayServer.screen_get_usable_rect(screen)
	if usable.size.x <= 0 or usable.size.y <= 0:
		return

	# Never expose a minimum size larger than the monitor itself.
	get_window().min_size = Vector2i(
		mini(COMPACT_MIN_SIZE.x, usable.size.x),
		mini(COMPACT_MIN_SIZE.y, usable.size.y)
	)

	var mode := DisplayServer.window_get_mode()
	if mode == DisplayServer.WINDOW_MODE_WINDOWED:
		var current := DisplayServer.window_get_size()
		var safe_max := Vector2i(
			maxi(1, floori(float(usable.size.x) * SCREEN_FILL)),
			maxi(1, floori(float(usable.size.y) * SCREEN_FILL))
		)
		var preferred := Vector2i(
			mini(DESIGN_SIZE.x, safe_max.x),
			mini(DESIGN_SIZE.y, safe_max.y)
		)

		# Respect a deliberately smaller saved window, but shrink windows that are
		# too large for the current monitor.
		var target := Vector2i(
			mini(current.x, preferred.x),
			mini(current.y, preferred.y)
		)
		target.x = maxi(target.x, mini(COMPACT_MIN_SIZE.x, safe_max.x))
		target.y = maxi(target.y, mini(COMPACT_MIN_SIZE.y, safe_max.y))

		if target != current:
			DisplayServer.window_set_size(target)
			_center_window(usable, target)

	_apply_layout_density(usable.size)


func _center_window(usable: Rect2i, window_size: Vector2i) -> void:
	var x := usable.position.x + maxi(0, roundi(float(usable.size.x - window_size.x) * 0.5))
	var y := usable.position.y + maxi(0, roundi(float(usable.size.y - window_size.y) * 0.5))
	DisplayServer.window_set_position(Vector2i(x, y))


func _on_window_size_changed() -> void:
	if not _bound or not is_instance_valid(_main):
		return
	var screen := DisplayServer.window_get_current_screen()
	var usable := DisplayServer.screen_get_usable_rect(screen)
	_apply_layout_density(usable.size)


func _apply_layout_density(screen_size: Vector2i) -> void:
	var window_size := DisplayServer.window_get_size()
	var compact := (
		screen_size.x <= COMPACT_BREAKPOINT.x
		or screen_size.y <= COMPACT_BREAKPOINT.y
		or window_size.x <= COMPACT_BREAKPOINT.x
		or window_size.y <= COMPACT_BREAKPOINT.y
	)

	var sidebar_width := 224.0 if compact else 270.0
	_sidebar.offset_right = sidebar_width
	_main_margin.offset_left = sidebar_width

	_main_margin.add_theme_constant_override("margin_left", 18 if compact else 30)
	_main_margin.add_theme_constant_override("margin_top", 14 if compact else 24)
	_main_margin.add_theme_constant_override("margin_right", 18 if compact else 30)
	_main_margin.add_theme_constant_override("margin_bottom", 14 if compact else 24)

	if _search != null:
		_search.custom_minimum_size.x = 250.0 if compact else 330.0

	var sidebar_margin := _main.get_node_or_null("Sidebar/SidebarMargin") as MarginContainer
	if sidebar_margin != null:
		sidebar_margin.add_theme_constant_override("margin_left", 14 if compact else 22)
		sidebar_margin.add_theme_constant_override("margin_top", 16 if compact else 26)
		sidebar_margin.add_theme_constant_override("margin_right", 14 if compact else 22)
		sidebar_margin.add_theme_constant_override("margin_bottom", 14 if compact else 22)

	var home := _main.get_node_or_null("MainMargin/MainVBox/HomeContent") as VBoxContainer
	if home != null:
		_apply_home_density(home, compact)


func _apply_home_density(home: VBoxContainer, compact: bool) -> void:
	if home.get_child_count() < 2:
		return
	var top_row := home.get_child(0) as HBoxContainer
	var bottom_row := home.get_child(1) as HBoxContainer
	if top_row != null:
		top_row.custom_minimum_size.y = 250.0 if compact else 310.0
		if top_row.get_child_count() >= 2:
			var agenda := top_row.get_child(1) as Control
			if agenda != null:
				agenda.custom_minimum_size.x = 300.0 if compact else 360.0
	if bottom_row != null and bottom_row.get_child_count() >= 2:
		var quick := bottom_row.get_child(1) as Control
		if quick != null:
			quick.custom_minimum_size.x = 300.0 if compact else 360.0
