extends CharacterBody3D

const SPEED = 5.0
const SPRINT_SPEED = 7.0
const GRAVITY = 24.0
var game

func _ready() -> void:
	game = get_tree().current_scene
	floor_snap_length = 0.35

func _physics_process(delta: float) -> void:
	if game == null or not game.active:
		velocity = Vector3.ZERO
		return
	var axes = Input.get_vector("move_left", "move_right", "move_forward", "move_back")
	var direction = Vector3(axes.x, 0, axes.y).rotated(Vector3.UP, game.camera_yaw)
	var current_speed = SPRINT_SPEED if Input.is_action_pressed("sprint") else SPEED
	velocity.x = move_toward(velocity.x, direction.x * current_speed, 28.0 * delta)
	velocity.z = move_toward(velocity.z, direction.z * current_speed, 28.0 * delta)
	if not is_on_floor():
		velocity.y -= GRAVITY * delta
	else:
		velocity.y = -0.1
	move_and_slide()
	if direction.length_squared() > 0.01:
		$Body.rotation.y = lerp_angle($Body.rotation.y, atan2(-direction.x, -direction.z), delta * 12.0)
	if position.y < -5.0:
		game.recover_player()
