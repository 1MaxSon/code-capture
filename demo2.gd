extends CharacterBody2D


@export var move_speed := 200
@export var run_speed := 350
@export var jump_force := 450
@export var gravity := 1200
@export var max_jumps := 2

var jumps_left := 0
var is_running := false
var is_facing_right := true

@onready var sprite := $AnimatedSprite2D
@onready var jump_sound := $JumpSound
@onready var land_sound := $LandSound


func _ready() -> void:
	jumps_left = max_jumps


func _physics_process(delta: float) -> void:
	handle_input()
	apply_gravity(delta)
	handle_movement(delta)
	update_animation()


func handle_input() -> void:
	is_running = Input.is_action_pressed("ui_accept")

	if is_on_floor():
		jumps_left = max_jumps

	if Input.is_action_just_pressed("ui_up") and jumps_left > 0:
		velocity.y = -jump_force
		jumps_left -= 1
		jump_sound.play()


func apply_gravity(delta: float) -> void:
	if not is_on_floor():
		velocity.y += gravity * delta
	else:
		if velocity.y > 0:
			velocity.y = 0
			land_sound.play()


func handle_movement(_delta: float) -> void:
	var direction := Input.get_action_strength("ui_right") - Input.get_action_strength("ui_left")
	var speed := run_speed if is_running else move_speed
	velocity.x = direction * speed

	if direction != 0:
		is_facing_right = direction > 0
		sprite.flip_h = not is_facing_right

	move_and_slide()


func update_animation() -> void:
	if not is_on_floor():
		sprite.play("jump")
	elif abs(velocity.x) > 10:
		sprite.play("run" if is_running else "walk")
	else:
		sprite.play("idle")
