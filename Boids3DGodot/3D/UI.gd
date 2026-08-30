extends CanvasLayer

@export var main: Node
@onready var fps_label: Label = %FPSLabel

@onready var boid_pos_texture_rect: TextureRect = %BoidDataTexture
@onready var boid_vel_texture_rect: TextureRect = %BoidVeloTexture
@onready var debug_label: Label = %DebugLabel
@onready var slider_menu: PanelContainer = %SliderMenu

#@export var num_boids:         int   = 350
#@export var world_radius:      int   = 10
#@export var simulate_gpu:      bool  = false

@export var is_2d := true
var slider_list

func _ready() -> void:
	if is_2d:
		slider_list = [
			["friend_radius",     0, 50],
			["avoid_radius",      0, 40],
			["min_vel",           0, 100],
			["max_vel",           0, 100],
			["steer_factor",      0, 100],
			["alignment_factor",  0, 100],
			["cohesion_factor",   0, 100],
			["separation_factor", 0, 100],
			["flow_factor",       0, 100],
			["mouse_factor",      0, 100],
			["avoidance_factor",  0, 100],
			["time_scale",        0, 4],
		]
	else:
		slider_list = [
			["friend_radius",     0, 5],
			["avoid_radius",      0, 5],
			["min_vel",           0, 100],
			["max_vel",           0, 100],
			["steer_factor",      0, 5],
			["alignment_factor",  0, 5],
			["cohesion_factor",   0, 5],
			["separation_factor", 0, 5],
			["flow_factor",       0, 5],
			["mouse_factor",      0, 5],
			["avoidance_factor",  0, 5],
			["time_scale",        0, 4],
		]
	
	slider_menu.add_sliders(slider_list)
	#Input.set_mouse_mode(Input.MOUSE_MODE_CAPTURED)
	General.viewing_changed.connect(func(state): visible = !state)


func _process(_wdelta: float) -> void:
	var fps_text = "Boids: " + str(main.NUM_BOIDS) + " / FPS: " + str(Engine.get_frames_per_second())
	fps_label.text = fps_text
	get_window().title = fps_text
	
	if main.get("boid_pos_texture") != null:
		boid_pos_texture_rect.texture = main.boid_pos_texture
	if main.get("boid_lerp_texture") != null:
		boid_vel_texture_rect.texture = main.boid_lerp_texture
