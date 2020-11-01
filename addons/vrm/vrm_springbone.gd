extends Resource


# Annotation comment
@export var comment: String

# The resilience of the swaying object (the power of returning to the initial pose).
@export  var stiffness_force: float = 1.0
 # (float, 0, 4)
# The strength of gravity.
@export  var gravity_power: float = 0.0
 # (float, 0, 2)
# The direction of gravity. Set (0, -1, 0) for simulating the gravity.
# Set (1, 0, 0) for simulating the wind.
@export var gravity_dir: Vector3 = Vector3(0.0, -1.0, 0.0)

# The resistance (deceleration) of automatic animation.
@export  var drag_force: float = 0.4
 # (float, 0, 1)
# Bone name references are only valid within a given Skeleton.
@export var skeleton: NodePath

# The reference point of a swaying object can be set at any location except the origin.
# When implementing UI moving with warp, the parent node to move with warp can be
# specified if you don't want to make the object swaying with warp movement.",
# Exactly one of the following must be set.
@export var center_bone: String = ""
@export var center_node: NodePath

# The radius of the sphere used for the collision detection with colliders.
@export  var hit_radius: float = 0.02
 # (float, 0.0, 0.5)
# bone name of the root bone of the swaying object, within skeleton.
@export  var root_bones : Array # DO NOT INITIALIZE HERE
 # (Array, String)
# Reference to the vrm_collidergroup for collisions with swaying objects.
@export var collider_groups : Array # DO NOT INITIALIZE HERE

# TODO: Allow switching between _process (LateUpdate) and _physics_process (FixedUpdate)




# Called when the node enters the scene tree for the first time.
func _ready():
	pass # Replace with function body.


# Called every frame. 'delta' is the elapsed time since the previous frame.
#func _process(delta):
#	pass
