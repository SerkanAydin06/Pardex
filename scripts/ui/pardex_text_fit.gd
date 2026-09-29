extends RefCounted

# Text policy for the PARDEX shell: single-line text reports its full width as
# its minimum size, which would push panels wider than the window. Such text
# ellipsizes instead, and descriptive "Body" paragraphs wrap.
#
# Text is only allowed to shrink where its container hands out width beyond the
# minimum (vertical stacks, grids, expanding row items); a non-expanding row
# item or an anchor-placed badge is sized by its minimum and would become "…".

const KEEP_FULL_TEXT := ["BrandP", "BrandA", "BrandR", "BrandD", "BrandE", "BrandX", "Avatar", "Mark"]


static func apply(node: Node) -> void:
	if node is Control and _may_shrink(node as Control):
		if node is Label:
			var label := node as Label
			if label.autowrap_mode == TextServer.AUTOWRAP_OFF:
				if String(label.name) == "Body":
					label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
				else:
					label.text_overrun_behavior = TextServer.OVERRUN_TRIM_ELLIPSIS
		elif node is Button:
			var button := node as Button
			if button.text != "" and button.text_overrun_behavior == TextServer.OVERRUN_NO_TRIMMING:
				button.text_overrun_behavior = TextServer.OVERRUN_TRIM_ELLIPSIS
				button.clip_text = true
	for child in node.get_children():
		apply(child)


static func _may_shrink(control: Control) -> bool:
	if String(control.name) in KEEP_FULL_TEXT:
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
