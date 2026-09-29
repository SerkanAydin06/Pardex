extends "res://scripts/ui/pardex_home_art.gd"

const ASSET_REMAP := {
	"res://assets/ui/ChatGPT Görseli 29 Eyl 2026 13_25_38-1.png": "res://assets/ui/home_hero_banner.png",
	"res://assets/ui/ChatGPT Görseli 29 Eyl 2026 13_25_40-2.png": "res://assets/ui/home_recent_gamepad.png",
	"res://assets/ui/ChatGPT Görseli 29 Eyl 2026 13_25_42-3.png": "res://assets/ui/home_recent_disc.png",
	"res://assets/ui/ChatGPT Görseli 29 Eyl 2026 13_25_44-4.png": "res://assets/ui/home_recent_grid.png",
	"res://assets/ui/ChatGPT Görseli 29 Eyl 2026 13_25_46-5.png": "res://assets/ui/home_recent_add.png",
	"res://assets/ui/ChatGPT Görseli 29 Eyl 2026 13_25_48-6.png": "res://assets/ui/home_agenda_announcement.png",
	"res://assets/ui/ChatGPT Görseli 29 Eyl 2026 13_25_50-7.png": "res://assets/ui/home_agenda_social.png",
	"res://assets/ui/ChatGPT Görseli 29 Eyl 2026 13_25_52-8.png": "res://assets/ui/home_agenda_games.png",
	"res://assets/ui/ChatGPT Görseli 29 Eyl 2026 13_25_58-9.png": "res://assets/ui/home_quick_add.png",
}

func _texture(path: String) -> Texture2D:
	var mapped_path := str(ASSET_REMAP.get(path, path))
	return ResourceLoader.load(mapped_path) as Texture2D
