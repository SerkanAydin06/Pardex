extends PanelContainer

# Active voice call strip (scenes/ui/call_bar.tscn): who, how long, whether
# they speak, and microphone / sound / hang-up buttons. Hidden without a call.

const MIC := preload("res://assets/ui/icons/mic.svg")
const MIC_OFF := preload("res://assets/ui/icons/mic_off.svg")
const SOUND := preload("res://assets/ui/icons/headphones.svg")
const SOUND_OFF := preload("res://assets/ui/icons/headphones_off.svg")
const QUALITY_GOOD := Color(0.204, 0.827, 0.6)
const QUALITY_FAIR := Color(0.984, 0.749, 0.141)
const QUALITY_POOR := Color(0.973, 0.443, 0.443)

var voice: Node
var _call: Dictionary = {}
var _peer_muted := false
# Local clock: the server PC's clock may differ from this one.
var _active_since := 0
# Connection quality: -1 until measured.
var _latency_ms := -1
var _loss_percent := -1.0


func setup(voice_node: Node) -> void:
	voice = voice_node
	PardexOnline.call_state_changed.connect(func(call_state: Dictionary):
		if str(call_state.get("state", "")) == "active" and str(_call.get("state", "")) != "active":
			_active_since = Time.get_ticks_msec()
		if str(call_state.get("state", "")) != "active":
			_latency_ms = -1
			_loss_percent = -1.0
		_call = call_state
		_peer_muted = false
		_refresh()
	)
	PardexOnline.call_ended.connect(func(_reason: String):
		_call = {}
		voice.set_muted(false)
		_refresh()
	)
	PardexOnline.call_peer_muted.connect(func(muted: bool):
		_peer_muted = muted
		_refresh()
	)
	PardexOnline.latency_changed.connect(func(milliseconds: int):
		_latency_ms = milliseconds
		_refresh_quality()
	)
	voice.packet_loss_changed.connect(func(percent: float):
		_loss_percent = percent
		_refresh_quality()
	)
	voice.remote_speaking_changed.connect(func(speaking: bool): ($Row/Info/NameRow/PeerSpeaking as Control).visible = speaking)
	($Row/MicButton as Button).pressed.connect(func():
		voice.set_muted(not voice.muted)
		_refresh()
	)
	($Row/DeafenButton as Button).pressed.connect(func():
		voice.set_deafened(not voice.deafened)
		_refresh()
	)
	($Row/HangupButton as Button).pressed.connect(PardexOnline.end_call)
	_refresh()


func _process(_delta: float) -> void:
	if visible and str(_call.get("state", "")) == "active":
		($Row/Info/Status as Label).text = _status_text()


func _refresh() -> void:
	visible = not _call.is_empty()
	set_process(visible)
	if not visible:
		return
	($Row/Info/NameRow/Name as Label).text = str(_call.get("peer_name", "Arkadaş"))
	($Row/Info/Status as Label).text = _status_text()
	var active := str(_call.get("state", "")) == "active"
	($Row/MicButton as Button).visible = active
	($Row/DeafenButton as Button).visible = active
	($Row/MicButton as Button).icon = MIC_OFF if voice.muted else MIC
	($Row/MicButton as Button).tooltip_text = "Mikrofonu aç" if voice.muted else "Mikrofonu kapat"
	($Row/DeafenButton as Button).icon = SOUND_OFF if voice.deafened else SOUND
	($Row/DeafenButton as Button).tooltip_text = "Sesi aç" if voice.deafened else "Sesi kapat"
	($Row/HangupButton as Button).tooltip_text = "Aramayı bitir" if active else "İptal et"
	_refresh_quality()


# "● İyi • 45 ms • %4 kayıp" under the call time; hidden until measured.
func _refresh_quality() -> void:
	var label := $Row/Info/Quality as Label
	label.visible = str(_call.get("state", "")) == "active" and _latency_ms >= 0
	if not label.visible:
		return
	var loss := maxf(_loss_percent, 0.0)
	var quality := "İyi"
	var color := QUALITY_GOOD
	if _latency_ms >= 300 or loss >= 10.0:
		quality = "Zayıf"
		color = QUALITY_POOR
	elif _latency_ms >= 150 or loss >= 3.0:
		quality = "Orta"
		color = QUALITY_FAIR
	var text := "● %s • %d ms" % [quality, _latency_ms]
	if loss >= 1.0:
		text += " • %%%d kayıp" % roundi(loss)
	label.text = text
	label.add_theme_color_override("font_color", color)


func _status_text() -> String:
	match str(_call.get("state", "")):
		"ringing":
			return "Aranıyor…" if bool(_call.get("outgoing", false)) else "Gelen arama"
		"active":
			var seconds := floori((Time.get_ticks_msec() - _active_since) / 1000.0)
			var text := "%02d:%02d" % [floori(seconds / 60.0), seconds % 60]
			if voice.muted:
				text += " • mikrofonun kapalı"
			if _peer_muted:
				text += " • karşı taraf sessizde"
			return text
	return ""
