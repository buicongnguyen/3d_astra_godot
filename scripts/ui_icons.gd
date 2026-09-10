extends RefCounted

# Imported once and shared by HUD controls; no per-frame image generation.
const TEXTURES = {
	"logo": preload("res://assets/ui/logo.svg"),
	"alloy": preload("res://assets/ui/alloy.svg"),
	"energy": preload("res://assets/ui/energy.svg"),
	"people": preload("res://assets/ui/people.svg"),
	"worker": preload("res://assets/ui/worker.svg"),
	"shield": preload("res://assets/ui/shield.svg"),
	"crosshair": preload("res://assets/ui/crosshair.svg"),
	"tank": preload("res://assets/ui/tank.svg"),
	"hq": preload("res://assets/ui/hq.svg"),
	"relay": preload("res://assets/ui/relay.svg"),
	"barracks": preload("res://assets/ui/barracks.svg"),
	"foundry": preload("res://assets/ui/foundry.svg"),
	"tower": preload("res://assets/ui/tower.svg"),
	"move": preload("res://assets/ui/move.svg"),
	"stop": preload("res://assets/ui/stop.svg"),
	"help": preload("res://assets/ui/help.svg"),
	"flag": preload("res://assets/ui/flag.svg"),
	"check": preload("res://assets/ui/check.svg"),
	"close": preload("res://assets/ui/close.svg"),
	"medic": preload("res://assets/ui/medic.svg"),
	"engineer": preload("res://assets/ui/engineer.svg"),
	"health": preload("res://assets/ui/health.svg"),
	"patrol": preload("res://assets/ui/patrol.svg"),
	"upgrade": preload("res://assets/ui/upgrade.svg"),
	"ranger": preload("res://assets/ui/ranger.svg"),
	"antitank": preload("res://assets/ui/antitank.svg"),
	"breaker": preload("res://assets/ui/breaker.svg"),
	"queue": preload("res://assets/ui/queue.svg"),
	"book": preload("res://assets/ui/book.svg"),
}
const ALIASES = {"vanguard":"shield", "attack":"crosshair", "support":"medic", "info":"book", "army":"people", "build":"worker"}

static func texture(key: String) -> Texture2D:
	return TEXTURES.get(ALIASES.get(key,key),TEXTURES.logo)
