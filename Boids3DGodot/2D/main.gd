extends Node2D

const NUM_BOIDS : int = 10000
var boid_pos = []
var boid_vel = []

var IMAGE_SIZE = int(ceil(sqrt(NUM_BOIDS)))
var boid_data : Image
var boid_data_texture : ImageTexture

@export_category("Boid Settings")
@export_range(0,100) var friend_radius = 18.0
@export_range(0,100) var avoid_radius = 12.0
@export_range(0,100) var min_vel = 20.0
@export_range(0,100) var max_vel = 30.0
@export_range(0,100) var steer_factor = 10.0
@export_range(0,100) var alignment_factor = 12.5
@export_range(0,100) var cohesion_factor = 21.5
@export_range(0,100) var separation_factor = 85.0
@export_range(0,100) var time_scale = 1.0

# GPU variables
var SIMULATE_GPU = true
var rd : RenderingDevice
var boid_compute_shader : RID
var pipeline : RID
var bindings : Array
var uniform_set : RID

var boid_pos_buffer : RID
var boid_vel_buffer : RID
var params_buffer : RID
var params_uniform : RDUniform
var boid_data_buffer : RID

@onready var viewport_size = get_viewport_rect().size
@onready var BoidParticle: GPUParticles2D = $BoidParticles

func _ready() -> void:
	randomize()
	_generate_boids()
	
	boid_data = Image.create(IMAGE_SIZE, IMAGE_SIZE, false, Image.FORMAT_RGBAH)
	boid_data_texture = ImageTexture.create_from_image(boid_data)
	
	BoidParticle.amount = NUM_BOIDS
	BoidParticle.process_material.set_shader_parameter("boid_data", boid_data_texture)
	
	if SIMULATE_GPU:
		_setup_compute_shader()
		_update_boids_gpu(0)


func _generate_boids():
	for i in NUM_BOIDS:
		boid_pos.append(Vector2(randf() * viewport_size.x, randf() * viewport_size.y))
		boid_vel.append(Vector2(randf_range(-1.0, 1.0) * max_vel, randf_range(-1.0, 1.0) * max_vel))


func _update_data_texture():
	if SIMULATE_GPU:
		var boid_data_image_data := rd.texture_get_data(boid_data_buffer, 0)
		boid_data.set_data(IMAGE_SIZE, IMAGE_SIZE, false, Image.FORMAT_RGBAH, boid_data_image_data)
	else:
		for i in NUM_BOIDS:
			var pixel_pos = Vector2(int(i % IMAGE_SIZE), int(i / float(IMAGE_SIZE)))
			boid_data.set_pixel(pixel_pos.x, pixel_pos.y, Color(boid_pos[i].x, boid_pos[i].y, boid_vel[i].angle(), 1.0))
	
	boid_data_texture.update(boid_data)


func _steer_toward(target: Vector2, heading: Vector2) -> Vector2:
	var tlen := target.length()
	if tlen < 1e-5: return Vector2.ZERO
	var desired : Vector2 = target / tlen * max_vel
	var v := desired - heading
	var mag := v.length()
	v = v.normalized() * min(mag, steer_factor) if (mag > 1e-5) else Vector2.ZERO
	return v


func _update_boids_cpu(delta):
	for i in NUM_BOIDS:
		var my_pos : Vector2 = boid_pos[i]
		var my_vel : Vector2 = boid_vel[i]
		var flock_heading = Vector2.ZERO
		var flock_center = Vector2.ZERO
		var separation_vec = Vector2.ZERO
		var friends : int = 0
		
		for j in NUM_BOIDS:
			if i == j: continue
			var other_pos = boid_pos[j]
			var offset : Vector2 = other_pos - my_pos
			var sq_dist = offset.x * offset.x + offset.y * offset.y
			
			if(sq_dist < friend_radius * friend_radius):
				var other_vel : Vector2 = boid_vel[j]
				flock_heading += other_vel.normalized();
				flock_center += other_pos;
				friends += 1
				
				if(sq_dist < avoid_radius * avoid_radius):
					separation_vec -= offset / max(sq_dist, 0.001)
		
		var acceleration := Vector2.ZERO
		
		if friends > 0:
			flock_center /= friends
			var flock_offset = flock_center - my_pos
			
			acceleration += _steer_toward(flock_heading, my_vel) * alignment_factor
			acceleration += _steer_toward(flock_offset, my_vel) * cohesion_factor
			acceleration += _steer_toward(separation_vec, my_vel) * separation_factor
		
		var dt : float = delta * time_scale
		
		my_vel += acceleration * dt
		var speed : float = my_vel.length()
		var dir : Vector2 = my_vel.normalized()
		speed = clampf(speed, min_vel, max_vel)
		my_vel = dir * speed
		my_pos += my_vel * dt
		
		my_pos = Vector2(wrapf(my_pos.x, 0, get_viewport_rect().size.x,),
						 wrapf(my_pos.y, 0, get_viewport_rect().size.y,))
		
		boid_pos[i] = my_pos
		boid_vel[i] = my_vel


func _generate_vec2_buffer(data) -> RID:
	var data_buffer_bytes := PackedVector2Array(data).to_byte_array()
	var data_buffer := rd.storage_buffer_create(data_buffer_bytes.size(), data_buffer_bytes)
	return data_buffer

func _generate_uniform(data_buffer, type, binding) -> RDUniform:
	var data_uniform := RDUniform.new()
	data_uniform.uniform_type = type
	data_uniform.binding = binding
	data_uniform.add_id(data_buffer)
	return data_uniform

func _generate_parameter_buffer(delta):
	var params_buffer_bytes := PackedFloat32Array(
	[NUM_BOIDS, IMAGE_SIZE, get_viewport_rect().size.x, get_viewport_rect().size.y,
	friend_radius, avoid_radius, min_vel*5, max_vel*5,
	steer_factor, alignment_factor, cohesion_factor, separation_factor,
	time_scale, delta]).to_byte_array()
	
	return rd.storage_buffer_create(params_buffer_bytes.size(), params_buffer_bytes)

func _setup_compute_shader():
	rd = RenderingServer.create_local_rendering_device()
	
	var shader_file := load("res://compute_shaders/boid_simulation_alt.glsl")
	var shader_spirv : RDShaderSPIRV = shader_file.get_spirv()
	boid_compute_shader = rd.shader_create_from_spirv(shader_spirv)
	pipeline = rd.compute_pipeline_create(boid_compute_shader)
	
	boid_pos_buffer = _generate_vec2_buffer(boid_pos)
	var boid_pos_uniform = _generate_uniform(boid_pos_buffer, RenderingDevice.UNIFORM_TYPE_STORAGE_BUFFER, 0)
	
	boid_vel_buffer = _generate_vec2_buffer(boid_vel)
	var boid_vel_uniform = _generate_uniform(boid_vel_buffer, RenderingDevice.UNIFORM_TYPE_STORAGE_BUFFER, 1)
	
	params_buffer = _generate_parameter_buffer(0)
	params_uniform = _generate_uniform(params_buffer, RenderingDevice.UNIFORM_TYPE_STORAGE_BUFFER, 2)
	
	var fmt := RDTextureFormat.new()
	fmt.width = IMAGE_SIZE
	fmt.height = IMAGE_SIZE
	fmt.format = RenderingDevice.DATA_FORMAT_R16G16B16A16_SFLOAT
	fmt.usage_bits = RenderingDevice.TEXTURE_USAGE_SAMPLING_BIT | RenderingDevice.TEXTURE_USAGE_STORAGE_BIT | RenderingDevice.TEXTURE_USAGE_CAN_UPDATE_BIT | RenderingDevice.TEXTURE_USAGE_CAN_COPY_FROM_BIT
	
	var view := RDTextureView.new()
	
	boid_data_buffer = rd.texture_create(fmt, view, [boid_data.get_data()])
	var boid_data_buffer_uniform = _generate_uniform(boid_data_buffer, RenderingDevice.UNIFORM_TYPE_IMAGE, 3)
	
	bindings = [boid_pos_uniform, boid_vel_uniform, params_uniform, boid_data_buffer_uniform]
	
	uniform_set = rd.uniform_set_create(bindings, boid_compute_shader, 0)


func _update_boids_gpu(delta):
	var new_params_data := PackedFloat32Array(
		[NUM_BOIDS, IMAGE_SIZE, get_viewport_rect().size.x, get_viewport_rect().size.y,
		friend_radius, avoid_radius, min_vel*5, max_vel*5,
		steer_factor, alignment_factor, cohesion_factor, separation_factor,
		time_scale, delta]).to_byte_array()
	
	rd.buffer_update(params_buffer, 0, new_params_data.size(), new_params_data)
	
	var compute_list := rd.compute_list_begin()
	rd.compute_list_bind_compute_pipeline(compute_list, pipeline)
	rd.compute_list_bind_uniform_set(compute_list, uniform_set, 0)
	rd.compute_list_dispatch(compute_list, ceil(NUM_BOIDS/1024.), 1, 1)
	rd.compute_list_end()
	rd.submit()


func _sync_boids_gpu():
	rd.sync()


func _process(delta: float) -> void:
	get_window().title = "Boids: " + str(NUM_BOIDS) + " / FPS: " + str(Engine.get_frames_per_second())
	
	if SIMULATE_GPU:
		_sync_boids_gpu()
	else:
		_update_boids_cpu(delta)
	
	_update_data_texture()
	
	if SIMULATE_GPU:
		_update_boids_gpu(delta)


func _free_gpu_resources():
	rd.free_rid(uniform_set)
	rd.free_rid(boid_data_buffer)
	rd.free_rid(params_buffer)
	rd.free_rid(boid_pos_buffer)
	rd.free_rid(boid_vel_buffer)
	rd.free_rid(pipeline)
	rd.free_rid(boid_compute_shader)


func _exit_tree():
	if SIMULATE_GPU:
		call_deferred("_free_gpu_resources")
