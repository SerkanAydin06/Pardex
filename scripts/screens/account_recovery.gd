extends PanelContainer

@onready var account_label: Label = $VBox/AccountRow/AccountValue
@onready var recovery_state_label: Label = $VBox/RecoveryState
@onready var generate_button: Button = $VBox/GenerateRow/GenerateButton
@onready var code_box: VBoxContainer = $VBox/CodeBox
@onready var code_edit: LineEdit = $VBox/CodeBox/CodeRow/CodeEdit
@onready var copy_button: Button = $VBox/CodeBox/CodeRow/CopyButton
@onready var recover_edit: LineEdit = $VBox/RecoverRow/RecoverCodeEdit
@onready var recover_button: Button = $VBox/RecoverRow/RecoverButton
@onready var status_label: Label = $VBox/Status

var _last_recovery_code := ""


func _ready() -> void:
	generate_button.pressed.connect(_on_generate_pressed)
	copy_button.pressed.connect(_on_copy_pressed)
	recover_button.pressed.connect(_on_recover_pressed)
	recover_edit.text_submitted.connect(func(_value: String): _on_recover_pressed())
	recover_edit.text_changed.connect(func(_value: String): _refresh_actions())
	PardexOnline.connection_state_changed.connect(_on_connection_state_changed)
	PardexOnline.welcome_received.connect(_on_welcome_received)
	PardexOnline.recovery_code_created.connect(_on_recovery_code_created)
	PardexOnline.account_recovered.connect(_on_account_recovered)
	PardexOnline.account_recovery_failed.connect(_on_recovery_failed)
	code_box.hide()
	_refresh_account_state()
	_refresh_actions()


func _on_generate_pressed() -> void:
	status_label.text = "Yeni tek kullanımlık kurtarma kodu hazırlanıyor…"
	status_label.add_theme_color_override("font_color", Color(0.88, 0.72, 0.34, 1))
	generate_button.disabled = true
	PardexOnline.request_recovery_code()


func _on_copy_pressed() -> void:
	if _last_recovery_code.is_empty():
		return
	DisplayServer.clipboard_set(_last_recovery_code)
	status_label.text = "Kurtarma kodu panoya kopyalandı. Güvenli bir yerde sakla."
	status_label.add_theme_color_override("font_color", Color(0.38, 0.86, 0.62, 1))


func _on_recover_pressed() -> void:
	var code := recover_edit.text.strip_edges()
	if code.is_empty():
		status_label.text = "Önce kurtarma kodunu gir."
		status_label.add_theme_color_override("font_color", Color(0.92, 0.46, 0.42, 1))
		return
	status_label.text = "Hesap doğrulanıyor ve bu cihaza bağlanıyor…"
	status_label.add_theme_color_override("font_color", Color(0.88, 0.72, 0.34, 1))
	recover_button.disabled = true
	generate_button.disabled = true
	PardexOnline.recover_account(code)


func _on_recovery_code_created(code: String) -> void:
	_last_recovery_code = code
	code_edit.text = code
	code_box.show()
	status_label.text = "Yeni kurtarma kodun hazır. Eski kod artık geçerli değildir."
	status_label.add_theme_color_override("font_color", Color(0.38, 0.86, 0.62, 1))
	_refresh_account_state()
	_refresh_actions()


func _on_account_recovered(_account_id: String, recovered_name: String) -> void:
	recover_edit.clear()
	_sync_recovered_profile(recovered_name)
	status_label.text = "Hesap kurtarıldı. Güvenlik için yeni tek kullanımlık kod oluşturuluyor…"
	status_label.add_theme_color_override("font_color", Color(0.38, 0.86, 0.62, 1))
	_refresh_account_state()
	PardexOnline.request_recovery_code()


func _on_recovery_failed(message: String) -> void:
	status_label.text = message
	status_label.add_theme_color_override("font_color", Color(0.92, 0.46, 0.42, 1))
	_refresh_account_state()
	_refresh_actions()


func _on_connection_state_changed(_state: String) -> void:
	_refresh_account_state()
	_refresh_actions()


func _on_welcome_received(_user_id: String, _display_name: String) -> void:
	_refresh_account_state()
	_refresh_actions()


func _refresh_account_state() -> void:
	var account_id := PardexOnline.account_id.strip_edges()
	# Same short PARDEX Kimliği as Profil (#TAG); the full id stays in the tooltip.
	account_label.text = ("#" + account_id.right(6).to_upper()) if not account_id.is_empty() else "Bağlantı bekleniyor"
	account_label.tooltip_text = account_id
	account_label.mouse_filter = Control.MOUSE_FILTER_PASS
	if not PardexOnline.is_online():
		recovery_state_label.text = "●  PARDEX ONLINE BAĞLANTISI BEKLENİYOR"
		recovery_state_label.add_theme_color_override("font_color", Color(0.88, 0.72, 0.34, 1))
	elif PardexOnline.recovery_enabled:
		recovery_state_label.text = "●  HESAP KURTARMA ETKİN"
		recovery_state_label.add_theme_color_override("font_color", Color(0.38, 0.86, 0.62, 1))
	else:
		recovery_state_label.text = "●  KURTARMA KODU HENÜZ OLUŞTURULMADI"
		recovery_state_label.add_theme_color_override("font_color", Color(0.72, 0.76, 0.84, 1))


func _refresh_actions() -> void:
	generate_button.disabled = not PardexOnline.is_online()
	recover_button.disabled = recover_edit.text.strip_edges().is_empty()


func _sync_recovered_profile(recovered_name: String) -> void:
	var normalized := recovered_name.strip_edges()
	if normalized.is_empty():
		return
	var main := get_tree().current_scene
	if main == null:
		return
	main.set("_display_name", normalized)
	if main.has_method("_apply_profile"):
		main.call("_apply_profile")
	if main.has_method("_save_settings"):
		main.call("_save_settings")
	var profile_edit := get_parent().get_node_or_null("ProfilePanel/VBox/ProfileRow/ProfileNameEdit") as LineEdit
	if profile_edit != null:
		profile_edit.text = normalized
