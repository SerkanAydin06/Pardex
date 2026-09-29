extends Node

# Responsive column controller for the existing Library GameGrid.
# It works after PardexAdaptiveWindow moves LibraryContent into its scroll body.

const RETRY_SECONDS := 0.20

var _grid: GridContainer
var _bound := false


func _ready() -> void:
	call_deferred("_bind")


func _bind() -> void:
	if _bound:
		return
	var tree := get_tree()
	if tree == null or tree.current_scene == null:
		_retry()
		return
	var scene := tree.current_scene
	if scene.name != "Pardex":
		_retry()
		return

	_grid = scene.get_node_or_null("MainMargin/MainVBox/LibraryContent/ResponsiveScroll/ResponsiveBody/GameGrid") as GridContainer
	if _grid == null:
		# AdaptiveWindow may still be building the scroll structure.
		_retry()
		return

	_bound = true
	_apply_columns()
	get_window().size_changed.connect(_on_window_size_changed)


func _retry() -> void:
	var tree := get_tree()
	if tree == null:
		return
	tree.create_timer(RETRY_SECONDS).timeout.connect(_bind)


func _on_window_size_changed() -> void:
	call_deferred("_apply_columns")


func _apply_columns() -> void:
	if _grid == null or not is_instance_valid(_grid):
		return
	var width := _grid.size.x
	if width <= 1.0:
		width = maxf(500.0, float(DisplayServer.window_get_size().x) - 260.0)

	if width >= 900.0:
		_grid.columns = 3
	elif width >= 620.0:
		_grid.columns = 2
	else:
		_grid.columns = 1

	var compact := width < 900.0
	_grid.add_theme_constant_override("h_separation", 12 if compact else 18)
	_grid.add_theme_constant_override("v_separation", 12 if compact else 18)

	for card in _grid.get_children():
		if card is Control:
			(card as Control).custom_minimum_size = Vector2(0, 330 if compact else 366)
