extends Node
var locale := "zh_CN"
var tables: Dictionary = {}
func configure(data: Dictionary) -> void:
	tables = data.duplicate(true)
	if not tables.has(locale): locale = "zh_CN"
	EventBus.locale_changed.emit()
func set_locale(value: String) -> bool:
	if not tables.has(value): return false
	locale = value
	EventBus.locale_changed.emit()
	return true
func text(value: String) -> String:
	if not value.begins_with("@"): return value
	var key := value.substr(1)
	return str(tables.get(locale, {}).get(key, tables.get("zh_CN", {}).get(key, value)))
