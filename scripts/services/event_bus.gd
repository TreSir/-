extends Node
## Optional services subscribe here; the interpreter never imports listeners.
signal game_started
signal flags_changed
signal inventory_changed
signal unlock_requested(id: String)
signal ending_reached(id: String, entry: String)
signal step_entered(id: String)
signal story_reloaded
signal locale_changed
signal notification(message: String)
signal custom_event(name: String, payload: Dictionary)
