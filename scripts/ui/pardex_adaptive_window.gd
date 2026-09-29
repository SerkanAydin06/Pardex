extends Node

# Steam-style responsive desktop shell for PARDEX.
# Layout reflows; text/icons stay readable and the home screen fills the viewport.
#
# Layout contract: the sidebar has a fixed width and MainMargin starts right after
# it. Nothing inside either panel may demand more width than it is given, so all
# single-line text ellipsizes instead of pushing panels over each other, and all
# reflow decisions use the width the window actually offers (not the width of the
# content, which would feed back into itself). Window size and minimum size are
# owned by main.gd.

const BIND_RETRY_SECONDS := 0.20
# Labels/buttons that must keep their full text (short, fixed-size UI).
const NO_SHRINK_NAMES := ["BrandP", "BrandA", "BrandR", "BrandD", "BrandE", "BrandX", "Avatar", "Mark"]

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
	_make_shrinkable(_main)
	tree.node_added.connect(_on_node_added)
	await tree.process_frame
	_apply_shell_density()
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

func _window_width() -> float:
	return _main.get_viewport_rect().size.x

# Width available to page content: window minus sidebar and the main margins.
func _content_width() -> float:
	var left := _main_margin.get_theme_constant("margin_left")
	var right := _main_margin.get_theme_constant("margin_right")
	return maxf(320.0, _window_width() - _main_margin.offset_left - float(left + right))

func _on_node_added(node: Node) -> void:
	if not is_instance_valid(_main) or not (node is Control) or not _main.is_ancestor_of(node):
		return
	_make_shrinkable(node)

# Single-line text reports its full width as minimum size; with an overrun
# behavior it can shrink, so long text never widens its panel.
func _make_shrinkable(node: Node) -> void:
	if node is Control and _may_shrink(node as Control):
		if node is Label:
			var label := node as Label
			if String(label.name) == "Body" and label.autowrap_mode == TextServer.AUTOWRAP_OFF:
				# Descriptive paragraphs wrap onto more lines instead of losing text.
				label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
			elif label.autowrap_mode == TextServer.AUTOWRAP_OFF:
				label.text_overrun_behavior = TextServer.OVERRUN_TRIM_ELLIPSIS
		elif node is Button:
			var button := node as Button
			if button.text != "" and button.text_overrun_behavior == TextServer.OVERRUN_NO_TRIMMING:
				button.text_overrun_behavior = TextServer.OVERRUN_TRIM_ELLIPSIS
				button.clip_text = true
	for child in node.get_children():
		_make_shrinkable(child)

# Only shrink text whose container hands out width beyond the minimum:
# vertical stacks, grids and expanding row items. A non-expanding item in a row,
# or a label placed by anchors, is sized by its minimum and would collapse to "…".
func _may_shrink(control: Control) -> bool:
	if String(control.name) in NO_SHRINK_NAMES:
		return false
	var item := control
	var parent := control.get_parent()
	while parent is PanelContainer or parent is MarginContainer:
		item = parent as Control
		parent = parent.get_parent()
	if not (parent is Container):
		return false
	if parent is BoxContainer and not (parent as BoxContainer).vertical:
		return (item.size_flags_horizontal & Control.SIZE_EXPAND) != 0
	return true

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
	var window_width := _window_width()
	var narrow := window_width <= WINDOW_NARROW
	var compact := window_width <= WINDOW_COMPACT
	# Reference keeps the navigation substantial even on a 1366-wide laptop.
	var sidebar_width := 232.0 if narrow else (250.0 if compact else 270.0)
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
		# The search box takes the free header space but never forces its width.
		_search.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		_search.size_flags_stretch_ratio = 1.0
		_search.custom_minimum_size = Vector2(120.0 if narrow else 180.0, maxf(48.0, _search.custom_minimum_size.y))
	var header_text := _main.get_node_or_null("MainMargin/MainVBox/Header/HeaderRow/HeaderText") as Control
	if header_text != null:
		# Keeps the page title readable; the subtitle ellipsizes below it.
		header_text.custom_minimum_size.x = 200.0 if narrow else 220.0
	var pill := _main.get_node_or_null("MainMargin/MainVBox/Header/HeaderRow/ConnectionPill") as Control
	if pill != null:
		pill.custom_minimum_size.x = 110.0 if narrow else 172.0
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
	var content_width := _content_width()
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
	# Grid columns share width by minimum size, so the side panels get a fixed
	# share of the content width instead of a hard 320px floor.
	var side_width := clampf(content_width * 0.34, 260.0, 440.0)
	_home_hero.custom_minimum_size = Vector2(content_width - side_width - gap if _home_top_grid.columns == 2 else 0.0, top_height)
	_home_agenda.custom_minimum_size = Vector2(side_width if _home_top_grid.columns == 2 else 0.0, top_height)
	_home_recent.custom_minimum_size = Vector2(content_width - side_width - gap if _home_bottom_grid.columns == 2 else 0.0, bottom_height)
	_home_quick.custom_minimum_size = Vector2(side_width if _home_bottom_grid.columns == 2 else 0.0, bottom_height)
	if _recent_grid != null:
		var recent_width := content_width - side_width - gap if _home_bottom_grid.columns == 2 else content_width
		_recent_grid.columns = clampi(floori((recent_width + 10.0) / 160.0), 1, 4)
		for card in _recent_grid.get_children():
			if card is Control:
				(card as Control).custom_minimum_size = Vector2(0.0, maxf(240.0, bottom_height - 42.0))
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
	var width := _content_width()
	var compact := width < 1000.0
	_library_body.add_theme_constant_override("separation", 12 if compact else 18)
	var hero := _library_body.get_node_or_null("Hero") as Control
	if hero != null:
		hero.custom_minimum_size = Vector2(0, 205 if compact else 244)
