@tool
extends EditorSceneImporter


enum DebugMode {
	None = 0,
	Normal = 1,
	LitShadeRate = 2,
}

enum OutlineColorMode {
	FixedColor = 0,
	MixedLighting = 1,
}

enum OutlineWidthMode {
	None = 0,
	WorldCoordinates = 1,
	ScreenCoordinates = 2,
}

enum RenderMode {
	Opaque = 0,
	Cutout = 1,
	Transparent = 2,
	TransparentWithZWrite = 3,
}

enum CullMode {
	Off = 0,
	Front = 1,
	Back = 2,
}

enum FirstPersonFlag {
	Auto, # Create headlessModel
	Both, # Default layer
	ThirdPersonOnly,
	FirstPersonOnly,
}
const FirstPersonParser: Dictionary = {
	"Auto": FirstPersonFlag.Auto,
	"Both": FirstPersonFlag.Both,
	"FirstPersonOnly": FirstPersonFlag.FirstPersonOnly,
	"ThirdPersonOnly": FirstPersonFlag.ThirdPersonOnly,
}

const USE_COMPAT_SHADER = false


func _get_extensions():
	return ["vrm"]


func _get_import_flags():
	return EditorSceneImporter.IMPORT_SCENE


func _import_animation(path: String, flags: int, bake_fps: int) -> Animation:
	return Animation.new()


func hasprop(d: Dictionary, k: String):
	for key in d:
		if str(key) == str(k):
			return true
	return false
func getprop(d: Dictionary, k: String):
	for key in d:
		if str(key) == str(k):
			return d[key]
	return d[null]
func getpropdef(d: Dictionary, k: String, defl: Variant):
	for key in d:
		if str(key) == str(k):
			return d[key]
	return defl

func _process_khr_material(orig_mat: StandardMaterial3D, gltf_mat_props: Dictionary) -> Material:
	# VRM spec requires support for the KHR_materials_unlit extension.
	if hasprop(gltf_mat_props,"extensions"):
		# TODO: Implement this extension upstream.
		if hasprop(getprop(gltf_mat_props,"extensions"),"KHR_materials_unlit"):
			# TODO: validate that this is sufficient.
			orig_mat.shading_mode = StandardMaterial3D.SHADING_MODE_UNSHADED
	return orig_mat


func _vrm_get_texture_info(gltf_images: Array, vrm_mat_props: Dictionary, unity_tex_name: String):
	var texture_info: Dictionary = {}
	texture_info["tex"] = null
	texture_info["offset"] = Vector3(0.0, 0.0, 0.0)
	texture_info["scale"] = Vector3(1.0, 1.0, 1.0)
	if hasprop(getprop(vrm_mat_props,"textureProperties"), unity_tex_name):
		var mainTexId: int = getprop(getprop(vrm_mat_props,"textureProperties"),unity_tex_name)
		var mainTexImage: ImageTexture = gltf_images[mainTexId]
		texture_info["tex"] = mainTexImage
	if hasprop(getprop(vrm_mat_props,"vectorProperties"), unity_tex_name):
		var offsetScale: Array = getprop(getprop(vrm_mat_props,"vectorProperties"),unity_tex_name)
		texture_info["offset"] = Vector3(offsetScale[0], offsetScale[1], 0.0)
		texture_info["scale"] =Vector3(offsetScale[2], offsetScale[3], 1.0)
	return texture_info


func _vrm_get_float(vrm_mat_props: Dictionary, key: String, def: float) -> float:
	return getpropdef(getprop(vrm_mat_props,"floatProperties"), key, def)

 
func _process_vrm_material(orig_mat: StandardMaterial3D, gltf_images: Array, vrm_mat_props: Dictionary) -> Material:
	var vrm_shader_name:String = str(getprop(vrm_mat_props, "shader"))
	if vrm_shader_name == "VRM_USE_GLTFSHADER":
		return orig_mat # It's already correct!
	
	if (vrm_shader_name == "Standard" or
		vrm_shader_name == "UniGLTF/UniUnlit" or
		vrm_shader_name == "VRM/UnlitTexture" or
		vrm_shader_name == "VRM/UnlitCutout" or
		vrm_shader_name == "VRM/UnlitTransparent"):
		printerr("Unsupported legacy VRM shader " + str(vrm_shader_name) + " on material " + str(orig_mat.resource_name))
		return orig_mat

	var maintex_info: Dictionary = _vrm_get_texture_info(gltf_images, vrm_mat_props, "_MainTex")

	if vrm_shader_name == "VRM/UnlitTransparentZWrite":
		if getpropdef(maintex_info,"tex",null) != null:
			orig_mat.albedo_texture = maintex_info["tex"]
			orig_mat.uv1_offset = maintex_info["offset"]
			orig_mat.uv1_scale = maintex_info["scale"]
		orig_mat.flags_unshaded = true
		orig_mat.params_depth_draw_mode = StandardMaterial3D.DEPTH_DRAW_ALWAYS
		orig_mat.flags_no_depth_test = false
		orig_mat.params_blend_mode = StandardMaterial3D.BLEND_MODE_MIX
		return orig_mat

	if vrm_shader_name != "VRM/MToon":
		printerr("Unknown VRM shader " + str(vrm_shader_name) + " on material " + str(orig_mat.resource_name))
		return orig_mat


	# Enum(Off,0,Front,1,Back,2) _CullMode

	var floatProperties = getprop(vrm_mat_props, "floatProperties")
	var outline_width_mode = int(getpropdef(floatProperties, "_OutlineWidthMode", 0))
	var blend_mode = int(getpropdef(floatProperties, "_BlendMode", 0))
	var cull_mode = int(getpropdef(floatProperties, "_CullMode", 2))
	var outl_cull_mode = int(getpropdef(floatProperties, "_OutlineCullMode", 1))
	if cull_mode == int(CullMode.Front) || (outl_cull_mode != int(CullMode.Front) && outline_width_mode != int(OutlineWidthMode.None)):
		printerr("VRM Material " + str(orig_mat.resource_name) + " has unsupported front-face culling mode: " +
			str(cull_mode) + "/" + str(outl_cull_mode))
	if outline_width_mode == int(OutlineWidthMode.ScreenCoordinates):
		printerr("VRM Material " + str(orig_mat.resource_name) + " uses screenspace outlines.")


	var mtooncompat_shader_base_path = "res://MToonCompat/mtooncompat"
	var mtoon_shader_base_path = "res://Godot-MToon-Shader/mtoon"
	if USE_COMPAT_SHADER:
		mtoon_shader_base_path = mtooncompat_shader_base_path

	var godot_outline_shader_name = null
	if outline_width_mode != int(OutlineWidthMode.None):
		godot_outline_shader_name = mtoon_shader_base_path + "_outline"

	var godot_shader_name = mtoon_shader_base_path
	if blend_mode == int(RenderMode.Opaque) or blend_mode == int(RenderMode.Cutout):
		# NOTE: Cutout is not separately implemented due to code duplication.
		if cull_mode == int(CullMode.Off):
			godot_shader_name = mtoon_shader_base_path + "_cull_off"
	elif blend_mode == int(RenderMode.Transparent):
		godot_shader_name = mtoon_shader_base_path + "_trans"
		if cull_mode == int(CullMode.Off):
			godot_shader_name = mtoon_shader_base_path + "_trans_cull_off"
	elif blend_mode == int(RenderMode.TransparentWithZWrite):
		godot_shader_name = mtoon_shader_base_path + "_trans_zwrite"
		if cull_mode == int(CullMode.Off):
			godot_shader_name = mtoon_shader_base_path + "_trans_zwrite_cull_off"

	var godot_shader: Shader = ResourceLoader.load(godot_shader_name + ".shader")
	var godot_shader_outline: Shader = null
	if godot_outline_shader_name:
		godot_shader_outline = ResourceLoader.load(godot_outline_shader_name + ".shader")

	var new_mat = ShaderMaterial.new()
	new_mat.resource_name = orig_mat.resource_name
	new_mat.shader = godot_shader
	if getpropdef(maintex_info, "tex", null) != null:
		new_mat.set_shader_param("_MainTex", getprop(maintex_info, "tex"))

	new_mat.set_shader_param("_MainTex_ST", Plane(
		getprop(maintex_info, "scale").x, getprop(maintex_info, "scale").y,
		getprop(maintex_info, "offset").x, getprop(maintex_info, "offset").y))

	for param_name in ["_MainTex", "_ShadeTexture", "_BumpMap", "_RimTexture", "_SphereAdd", "_EmissionMap", "_OutlineWidthTexture", "_UvAnimMaskTexture"]:
		var tex_info: Dictionary = _vrm_get_texture_info(gltf_images, vrm_mat_props, param_name)
		if getpropdef(tex_info, "tex", null) != null:
			new_mat.set_shader_param(param_name, getprop(tex_info,"tex"))

	for param_name in floatProperties:
		new_mat.set_shader_param(str(param_name), floatProperties[param_name])
		
	for param_name in ["_Color", "_ShadeColor", "_RimColor", "_EmissionColor", "_OutlineColor"]:
		if hasprop(getprop(vrm_mat_props, "vectorProperties"), param_name):
			var param_val = getprop(getprop(vrm_mat_props, "vectorProperties"), param_name)
			#### TODO: Use Color
			### But we want to keep 4.0 compat which does not gamma correct color.
			var color_param: Plane = Plane(param_val[0], param_val[1], param_val[2], param_val[3])
			new_mat.set_shader_param(param_name, color_param)

	# FIXME: setting _Cutoff to disable cutoff is a bit unusual.
	if blend_mode == int(RenderMode.Cutout):
		new_mat.set_shader_param("_EnableAlphaCutout", 1.0)
	
	if godot_shader_outline != null:
		var outline_mat = new_mat.duplicate()
		outline_mat.shader = godot_shader_outline
		
		new_mat.next_pass = outline_mat
		
	# TODO: render queue -> new_mat.render_priority

	return new_mat


func _update_materials(vrm_extension: Dictionary, gstate: GLTFState):
	var images = gstate.get_images()
	#print(images)
	var materials : Array = gstate.get_materials();
	var spatial_to_shader_mat : Dictionary = {}
	for i in range(materials.size()):
		var oldmat: Material = materials[i]
		if (oldmat is ShaderMaterial):
			print("Material " + str(i) + ": " + str(oldmat.resource_name) + " already is shader.")
			continue
		var newmat: Material = _process_khr_material(oldmat, getprop(gstate.json, "materials")[i])
		newmat = _process_vrm_material(newmat, images, getprop(vrm_extension, "materialProperties")[i])
		spatial_to_shader_mat[oldmat] = newmat
		spatial_to_shader_mat[newmat] = newmat
		#print("Replacing shader " + str(oldmat) + "/" + oldmat.resource_name + " with " + str(newmat) + "/" + newmat.resource_name)
		materials[i] = newmat
		var oldpath = oldmat.resource_path
		oldmat.resource_path = ""
		newmat.take_over_path(oldpath)
		ResourceSaver.save(oldpath, newmat)
	gstate.set_materials(materials)

	var meshes = gstate.get_meshes()
	for i in range(meshes.size()):
		var gltfmesh: GLTFMesh = meshes[i]
		var mesh: EditorSceneImporterMesh = gltfmesh.get_mesh()
		var mesh_new: EditorSceneImporterMesh = EditorSceneImporterMesh.new()

		########### FIXME: This is not currently possible in GDSCript #### mesh.blend_shape_mode = ArrayMesh.BLEND_SHAPE_MODE_NORMALIZED
		for blend_idx in range(mesh.get_blend_shape_count()):
			print("Adding new blend shape " + str(mesh_new.get_blend_shape_count()))
			mesh_new.add_blend_shape(mesh.get_blend_shape_name(blend_idx))
		for surf_idx in range(mesh.get_surface_count()):
			var surfmat = mesh.get_surface_material(surf_idx)
			if not spatial_to_shader_mat.has(surfmat):
				printerr("Mesh " + str(i) + " material " + str(surf_idx) + " name " + str(surfmat.resource_name) + " has no replacement material.")
			var blends = []
			for bi in range(mesh.get_blend_shape_count()):
				blends.append(mesh.get_surface_blend_shape_arrays(surf_idx, bi))
			print("Surface new " + str(surf_idx) + " adding " + str(len(blends)) + " blend shapes " + str(mesh_new.get_blend_shape_count()) + "/" + str(mesh.get_blend_shape_count()))
			var lods = {}
			for lod in range(mesh.get_surface_lod_count(surf_idx)):
				lods[mesh.get_surface_lod_size(surf_idx, lod)] = mesh.get_surface_lod_indices(surf_idx, lod)
			mesh_new.add_surface(
				mesh.get_surface_primitive_type(surf_idx),
				mesh.get_surface_arrays(surf_idx),
				blends,
				lods,
				spatial_to_shader_mat.get(surfmat, mesh.get_surface_material(surf_idx)),
				mesh.get_surface_name(surf_idx))
		mesh.clear()
		for blend_idx in range(mesh_new.get_blend_shape_count()):
			print("Adding blend shape " + str(mesh.get_blend_shape_count()))
			mesh.add_blend_shape(mesh_new.get_blend_shape_name(blend_idx))
		for surf_idx in range(mesh_new.get_surface_count()):
			var surfmat = mesh_new.get_surface_material(surf_idx)
			var blends = []
			for bi in range(mesh_new.get_blend_shape_count()):
				blends.append(mesh_new.get_surface_blend_shape_arrays(surf_idx, bi))
			print("Surface new " + str(surf_idx) + " adding " + str(len(blends)) + " blend shapes " + str(mesh.get_blend_shape_count()) + "/" + str(mesh_new.get_blend_shape_count()))
			var lods = {}
			for lod in range(mesh_new.get_surface_lod_count(surf_idx)):
				lods[mesh_new.get_surface_lod_size(surf_idx, lod)] = mesh_new.get_surface_lod_indices(surf_idx, lod)
			mesh.add_surface(
				mesh_new.get_surface_primitive_type(surf_idx),
				mesh_new.get_surface_arrays(surf_idx),
				blends,
				lods,
				mesh_new.get_surface_material(surf_idx),
				mesh_new.get_surface_name(surf_idx))
		# gltfmesh.set_mesh(mesh_new)


func poolintarray_find(arr: PackedInt32Array, val: int) -> int:
	for i in range(arr.size()):
		if arr[i] == val:
			return i
	return -1


func _get_skel_godot_node(gstate: GLTFState, nodes: Array, skeletons: Array, skel_id: int) -> Node:
	# There's no working direct way to convert from skeleton_id to node_id.
	# Bugs:
	# GLTFNode.parent is -1 if skeleton bone.
	# skeleton_to_node is empty
	# get_scene_node(skeleton bone) works though might maybe return an attachment.
	# var skel_node_idx = nodes[gltfskel.roots[0]]
	# return gstate.get_scene_node(skel_node_idx) # as Skeleton
	for i in range(nodes.size()):
		if nodes[i].skeleton == skel_id:
			return gstate.get_scene_node(i)
	return null

class SkelBone:
	var skel: Skeleton3D
	var bone_name: String
	

# https://github.com/vrm-c/vrm-specification/blob/master/specification/0.0/schema/vrm.humanoid.bone.schema.json
# vrm_extension["humanoid"]["bone"]:
#"enum": ["hips","leftUpperLeg","rightUpperLeg","leftLowerLeg","rightLowerLeg","leftFoot","rightFoot",
# "spine","chest","neck","head","leftShoulder","rightShoulder","leftUpperArm","rightUpperArm",
# "leftLowerArm","rightLowerArm","leftHand","rightHand","leftToes","rightToes","leftEye","rightEye","jaw",
# "leftThumbProximal","leftThumbIntermediate","leftThumbDistal",
# "leftIndexProximal","leftIndexIntermediate","leftIndexDistal",
# "leftMiddleProximal","leftMiddleIntermediate","leftMiddleDistal",
# "leftRingProximal","leftRingIntermediate","leftRingDistal",
# "leftLittleProximal","leftLittleIntermediate","leftLittleDistal",
# "rightThumbProximal","rightThumbIntermediate","rightThumbDistal",
# "rightIndexProximal","rightIndexIntermediate","rightIndexDistal",
# "rightMiddleProximal","rightMiddleIntermediate","rightMiddleDistal",
# "rightRingProximal","rightRingIntermediate","rightRingDistal",
# "rightLittleProximal","rightLittleIntermediate","rightLittleDistal", "upperChest"]


func _create_meta(root_node: Node, animplayer: AnimationPlayer, vrm_extension: Dictionary, gstate: GLTFState, human_bone_to_idx: Dictionary) -> Resource:
	var nodes = gstate.get_nodes()
	var skeletons = gstate.get_skeletons()
	var hipsNode: GLTFNode = nodes[getprop(human_bone_to_idx, "hips")]
	var skeleton: Skeleton3D = _get_skel_godot_node(gstate, nodes, skeletons, hipsNode.skeleton)
	var skeletonPath: NodePath = root_node.get_path_to(skeleton)
	root_node.set("vrm_skeleton", skeletonPath)

	var animPath: NodePath = root_node.get_path_to(animplayer)
	root_node.set("vrm_animplayer", animPath)

	var firstperson = vrm_extension.get("firstPerson", null)
	var eyeOffset: Vector3;

	if firstperson:
		# FIXME: Technically this is supposed to be offset relative to the "firstPersonBone"
		# However, firstPersonBone defaults to Head...
		# and the semantics of a VR player having their viewpoint out of something which does
		# not rotate with their head is unclear.
		# Additionally, the spec schema says this:
		# "It is assumed that an offset from the head bone to the VR headset is added."
		# Which implies that the Head bone is used, not the firstPersonBone.
		var fpboneoffsetxyz = getprop(firstperson,"firstPersonBoneOffset") # example: 0,0.06,0
		eyeOffset = Vector3(getprop(fpboneoffsetxyz, "x"), getprop(fpboneoffsetxyz, "y"), getprop(fpboneoffsetxyz, "z"))

	var gltfnodes: Array = gstate.nodes

	var humanBoneDictionary: Dictionary = {}
	for humanBoneName in human_bone_to_idx:
		humanBoneDictionary[str(humanBoneName)] = gltfnodes[getprop(human_bone_to_idx, humanBoneName)].resource_name

	var vrm_meta: Resource = load("res://addons/vrm/vrm_meta.gd").new()

	vrm_meta.resource_name = "CLICK TO SEE METADATA"
	vrm_meta.exporter_version = getpropdef(vrm_extension, "exporterVersion", "")
	vrm_meta.spec_version = getpropdef(vrm_extension, "specVersion", "")
	var vrm_extension_meta = getprop(vrm_extension, "meta")
	if vrm_extension_meta:
		vrm_meta.title = getpropdef(vrm_extension_meta, "title", "")
		vrm_meta.version = getpropdef(vrm_extension_meta, "version", "")
		vrm_meta.author = getpropdef(vrm_extension_meta, "author", "")
		vrm_meta.contact_information = getpropdef(vrm_extension_meta, "contactInformation", "")
		vrm_meta.reference_information = getpropdef(vrm_extension_meta, "reference", "")
		var tex: int = getpropdef(vrm_extension_meta, "texture", -1)
		if tex >= 0:
			var gltftex: GLTFTexture = gstate.get_textures()[tex]
			vrm_meta.texture = gstate.get_images()[gltftex.src_image]
		vrm_meta.allowed_user_name = getpropdef(vrm_extension_meta, "allowedUserName", "")
		vrm_meta.violent_usage = getpropdef(vrm_extension_meta, "violentUssageName", "") # Ussage (sic.) in VRM spec
		vrm_meta.sexual_usage = getpropdef(vrm_extension_meta, "sexualUssageName", "") # Ussage (sic.) in VRM spec
		vrm_meta.commercial_usage = getpropdef(vrm_extension_meta, "commercialUssageName", "") # Ussage (sic.) in VRM spec
		vrm_meta.other_permission_url = getpropdef(vrm_extension_meta, "otherPermissionUrl", "")
		vrm_meta.license_name = getpropdef(vrm_extension_meta, "licenseName", "")
		vrm_meta.other_license_url = getpropdef(vrm_extension_meta, "otherLicenseUrl", "")

	vrm_meta.eye_offset = eyeOffset
	vrm_meta.humanoid_bone_mapping = humanBoneDictionary
	return vrm_meta.duplicate(true)


func _create_animation_player(animplayer: AnimationPlayer, vrm_extension: Dictionary, gstate: GLTFState, human_bone_to_idx: Dictionary) -> AnimationPlayer:
	# Remove all glTF animation players for safety.
	# VRM does not support animation import in this way.
	for i in range(gstate.get_animation_players_count(0)):
		var node: AnimationPlayer = gstate.get_animation_player(i)
		node.get_parent().remove_child(node)

	var meshes = gstate.get_meshes()
	var nodes = gstate.get_nodes()
	var blend_shape_groups = getprop(getprop(vrm_extension, "blendShapeMaster"), "blendShapeGroups")
	# FIXME: Do we need to handle multiple references to the same mesh???
	var mesh_idx_to_meshinstance : Dictionary = {}
	var material_name_to_mesh_and_surface_idx: Dictionary = {}
	for i in range(meshes.size()):
		var gltfmesh : GLTFMesh = meshes[i]
		for j in range(int(gltfmesh.get_mesh().get_surface_count())):
			material_name_to_mesh_and_surface_idx[gltfmesh.get_mesh().get_surface_material(j).resource_name] = [i, j]
			
	for i in range(nodes.size()):
		var gltfnode: GLTFNode = nodes[i]
		var mesh_idx: int = gltfnode.mesh
		#print("node idx " + str(i) + " node name " + gltfnode.resource_name + " mesh idx " + str(mesh_idx))
		if (mesh_idx != -1):
			var scenenode: MeshInstance3D = gstate.get_scene_node(i)
			mesh_idx_to_meshinstance[mesh_idx] = scenenode
			#print("insert " + str(mesh_idx) + " node name " + scenenode.name)

	for shape in blend_shape_groups:
		#print("Blend shape group: " + shape["name"])
		var anim = Animation.new()
		
		for matbind in getprop(shape, "materialValues"):
			var mesh_and_surface_idx = material_name_to_mesh_and_surface_idx[getprop(matbind, "materialName")]
			var node: MeshInstance3D = mesh_idx_to_meshinstance[mesh_and_surface_idx[0]]
			var surface_idx = mesh_and_surface_idx[1]

			var mat: Material = node.get_surface_material(surface_idx)
			var paramprop = "shader_param/" + getprop(matbind, "parameterName")
			var origvalue = null
			var tv = getprop(matbind, "targetValue")
			var newvalue = tv[0]
				
			if (mat is ShaderMaterial):
				var smat: ShaderMaterial = mat
				var param = smat.get_shader_param(getprop(matbind, "parameterName"))
				if param is Color:
					origvalue = param
					newvalue = Color(tv[0], tv[1], tv[2], tv[3])
				elif getprop(matbind, "parameterName") == "_MainTex" or getprop(matbind, "parameterName") == "_MainTex_ST":
					origvalue = param
					newvalue = Plane(tv[2], tv[3], tv[0], tv[1]) if getprop(matbind, "parameterName") == "_MainTex" else Plane(tv[0], tv[1], tv[2], tv[3])
				elif param is float:
					origvalue = param
					newvalue = tv[0]
				else:
					printerr("Unknown type for parameter " + getprop(matbind, "parameterName") + " surface " + node.name + "/" + str(surface_idx))

			if origvalue != null:
				var animtrack: int = anim.add_track(Animation.TYPE_VALUE)
				anim.track_set_path(animtrack, str(animplayer.get_parent().get_path_to(node)) + ":mesh:surface_" + str(surface_idx) + "/material:" + str(paramprop))
				anim.track_set_interpolation_type(animtrack, Animation.INTERPOLATION_NEAREST if bool(getprop(shape, "isBinary")) else Animation.INTERPOLATION_LINEAR)
				anim.track_insert_key(animtrack, 0.0, origvalue)
				anim.track_insert_key(animtrack, 0.0, newvalue)
		for bind in getprop(shape, "binds"):
			# FIXME: Is this a mesh_idx or a node_idx???
			var node: EditorSceneImporterMeshNode3D = mesh_idx_to_meshinstance[int(getprop(bind,"mesh"))]
			var nodeMesh: EditorSceneImporterMesh = node.get_mesh();
			
			if (getprop(bind, "index") < 0 || getprop(bind, "index") >= nodeMesh.get_blend_shape_count()):
				printerr("Invalid blend shape index in bind " + str(shape) + " for mesh " + str(node.name))
				continue
			var animtrack: int = anim.add_track(Animation.TYPE_VALUE)
			# nodeMesh.set_blend_shape_name(int(bind["index"]), shape["name"] + "_" + str(bind["index"]))
			anim.track_set_path(animtrack, str(animplayer.get_parent().get_path_to(node)) + ":blend_shapes/" + str(nodeMesh.get_blend_shape_name(int(getprop(bind, "index")))))
			var interpolation: int = Animation.INTERPOLATION_LINEAR
			if hasprop(shape, "isBinary") and bool(getprop(shape, "isBinary")):
				interpolation = Animation.INTERPOLATION_NEAREST
			anim.track_set_interpolation_type(animtrack, interpolation)
			anim.track_insert_key(animtrack, 0.0, float(0.0))
			# FIXME: Godot has weird normal/tangent singularities at weight=1.0 or weight=0.5
			# So we multiply by 0.99999 to produce roughly the same output, avoiding these singularities.
			anim.track_insert_key(animtrack, 1.0, 0.99999 * float(getprop(bind, "weight")) / 100.0)
			#var mesh:ArrayMesh = meshes[bind["mesh"]].mesh
			#print("Mesh name: " + mesh.resource_name)
			#print("Bind index: " + str(bind["index"]))
			#print("Bind weight: " + str(float(bind["weight"]) / 100.0))

		# https://github.com/vrm-c/vrm-specification/tree/master/specification/0.0#blendshape-name-identifier
		animplayer.add_animation(getprop(shape, "name").to_upper() if getprop(shape, "presetName") == "unknown" else getprop(shape, "presetName").to_upper(), anim)

	var firstperson = getprop(vrm_extension, "firstPerson")
	
	var firstpersanim: Animation = Animation.new()
	animplayer.add_animation("FirstPerson", firstpersanim)

	var thirdpersanim: Animation = Animation.new()
	animplayer.add_animation("ThirdPerson", thirdpersanim)

	var skeletons:Array = gstate.get_skeletons()

	var head_bone_idx = getpropdef(firstperson, "firstPersonBone", -1)
	if (head_bone_idx >= 0):
		var headNode: GLTFNode = nodes[head_bone_idx]
		var skeletonPath:NodePath = animplayer.get_parent().get_path_to(_get_skel_godot_node(gstate, nodes, skeletons, headNode.skeleton))
		var headBone: String = headNode.resource_name
		var firstperstrack = firstpersanim.add_track(Animation.TYPE_METHOD)
		firstpersanim.track_set_path(firstperstrack, ".")
		firstpersanim.track_insert_key(firstperstrack, 0.0, {"method": "TODO_scale_bone", "args": [skeletonPath, headBone, 0.0]})
		var thirdperstrack = thirdpersanim.add_track(Animation.TYPE_METHOD)
		thirdpersanim.track_set_path(thirdperstrack, ".")
		thirdpersanim.track_insert_key(thirdperstrack, 0.0, {"method": "TODO_scale_bone", "args": [skeletonPath, headBone, 1.0]})

	for meshannotation in getprop(firstperson, "meshAnnotations"):

		var flag = FirstPersonParser.get(getprop(meshannotation, "firstPersonFlag"), -1)
		var first_person_visibility;
		var third_person_visibility;
		if flag == FirstPersonFlag.ThirdPersonOnly:
			first_person_visibility = 0.0
			third_person_visibility = 1.0
		elif flag == FirstPersonFlag.FirstPersonOnly:
			first_person_visibility = 1.0
			third_person_visibility = 0.0
		else:
			continue
		var node: MeshInstance3D = mesh_idx_to_meshinstance[int(getprop(meshannotation, "mesh"))]
		var firstperstrack = firstpersanim.add_track(Animation.TYPE_VALUE)
		firstpersanim.track_set_path(firstperstrack, str(animplayer.get_parent().get_path_to(node)) + ":visible")
		firstpersanim.track_insert_key(firstperstrack, 0.0, first_person_visibility)
		var thirdperstrack = thirdpersanim.add_track(Animation.TYPE_VALUE)
		thirdpersanim.track_set_path(thirdperstrack, str(animplayer.get_parent().get_path_to(node)) + ":visible")
		thirdpersanim.track_insert_key(thirdperstrack, 0.0, third_person_visibility)

	if getpropdef(firstperson, "lookAtTypeName", "") == "Bone":
		var horizout = getprop(firstperson, "lookAtHorizontalOuter")
		var horizin = getprop(firstperson, "lookAtHorizontalInner")
		var vertup = getprop(firstperson, "lookAtVerticalUp")
		var vertdown = getprop(firstperson, "lookAtVerticalDown")
		var leftEyeNode: GLTFNode = nodes[getprop(human_bone_to_idx, "leftEye")]
		var skeleton:Skeleton3D = _get_skel_godot_node(gstate, nodes, skeletons,leftEyeNode.skeleton)
		var skeletonPath:NodePath = animplayer.get_parent().get_path_to(skeleton)
		var leftEyePath: String = str(skeletonPath) + ":" + nodes[getprop(human_bone_to_idx, "leftEye")].resource_name
		var rightEyeNode: GLTFNode = nodes[getprop(human_bone_to_idx, "rightEye")]
		skeleton = _get_skel_godot_node(gstate, nodes, skeletons,rightEyeNode.skeleton)
		skeletonPath = animplayer.get_parent().get_path_to(skeleton)
		var rightEyePath:String = str(skeletonPath) + ":" + nodes[getprop(human_bone_to_idx, "rightEye")].resource_name

		var anim = animplayer.get_animation("LOOKLEFT")
		if anim:
			var animtrack = anim.add_track(Animation.TYPE_TRANSFORM)
			anim.track_set_path(animtrack, leftEyePath)
			anim.track_set_interpolation_type(animtrack, Animation.INTERPOLATION_LINEAR)
			anim.transform_track_insert_key(animtrack, 0.0, Vector3.ZERO, Quat.IDENTITY, Vector3.ONE)
			anim.transform_track_insert_key(animtrack, getprop(horizout, "xRange") / 90.0, Vector3.ZERO, Basis(Vector3(0,1,0), getprop(horizout, "yRange") * 3.14159/180.0).get_rotation_quat(), Vector3.ONE)
			animtrack = anim.add_track(Animation.TYPE_TRANSFORM)
			anim.track_set_path(animtrack, rightEyePath)
			anim.track_set_interpolation_type(animtrack, Animation.INTERPOLATION_LINEAR)
			anim.transform_track_insert_key(animtrack, 0.0, Vector3.ZERO, Quat.IDENTITY, Vector3.ONE)
			anim.transform_track_insert_key(animtrack, getprop(horizin, "xRange") / 90.0, Vector3.ZERO, Basis(Vector3(0,1,0), getprop(horizin, "yRange") * 3.14159/180.0).get_rotation_quat(), Vector3.ONE)

		anim = animplayer.get_animation("LOOKRIGHT")
		if anim:
			var animtrack = anim.add_track(Animation.TYPE_TRANSFORM)
			anim.track_set_path(animtrack, leftEyePath)
			anim.track_set_interpolation_type(animtrack, Animation.INTERPOLATION_LINEAR)
			anim.transform_track_insert_key(animtrack, 0.0, Vector3.ZERO, Quat.IDENTITY, Vector3.ONE)
			anim.transform_track_insert_key(animtrack, getprop(horizin, "xRange") / 90.0, Vector3.ZERO, Basis(Vector3(0,1,0), -getprop(horizin, "yRange") * 3.14159/180.0).get_rotation_quat(), Vector3.ONE)
			animtrack = anim.add_track(Animation.TYPE_TRANSFORM)
			anim.track_set_path(animtrack, rightEyePath)
			anim.track_set_interpolation_type(animtrack, Animation.INTERPOLATION_LINEAR)
			anim.transform_track_insert_key(animtrack, 0.0, Vector3.ZERO, Quat.IDENTITY, Vector3.ONE)
			anim.transform_track_insert_key(animtrack, getprop(horizout, "xRange") / 90.0, Vector3.ZERO, Basis(Vector3(0,1,0), -getprop(horizout, "yRange") * 3.14159/180.0).get_rotation_quat(), Vector3.ONE)

		anim = animplayer.get_animation("LOOKUP")
		if anim:
			var animtrack = anim.add_track(Animation.TYPE_TRANSFORM)
			anim.track_set_path(animtrack, leftEyePath)
			anim.track_set_interpolation_type(animtrack, Animation.INTERPOLATION_LINEAR)
			anim.transform_track_insert_key(animtrack, 0.0, Vector3.ZERO, Quat.IDENTITY, Vector3.ONE)
			anim.transform_track_insert_key(animtrack, getprop(vertup, "xRange") / 90.0, Vector3.ZERO, Basis(Vector3(1,0,0), getprop(vertup, "yRange") * 3.14159/180.0).get_rotation_quat(), Vector3.ONE)
			animtrack = anim.add_track(Animation.TYPE_TRANSFORM)
			anim.track_set_path(animtrack, rightEyePath)
			anim.track_set_interpolation_type(animtrack, Animation.INTERPOLATION_LINEAR)
			anim.transform_track_insert_key(animtrack, 0.0, Vector3.ZERO, Quat.IDENTITY, Vector3.ONE)
			anim.transform_track_insert_key(animtrack, getprop(vertup, "xRange") / 90.0, Vector3.ZERO, Basis(Vector3(1,0,0), getprop(vertup, "yRange") * 3.14159/180.0).get_rotation_quat(), Vector3.ONE)

		anim = animplayer.get_animation("LOOKDOWN")
		if anim:
			var animtrack = anim.add_track(Animation.TYPE_TRANSFORM)
			anim.track_set_path(animtrack, leftEyePath)
			anim.track_set_interpolation_type(animtrack, Animation.INTERPOLATION_LINEAR)
			anim.transform_track_insert_key(animtrack, 0.0, Vector3.ZERO, Quat.IDENTITY, Vector3.ONE)
			anim.transform_track_insert_key(animtrack, getprop(vertdown, "xRange") / 90.0, Vector3.ZERO, Basis(Vector3(1,0,0), -getprop(vertdown, "yRange") * 3.14159/180.0).get_rotation_quat(), Vector3.ONE)
			animtrack = anim.add_track(Animation.TYPE_TRANSFORM)
			anim.track_set_path(animtrack, rightEyePath)
			anim.track_set_interpolation_type(animtrack, Animation.INTERPOLATION_LINEAR)
			anim.transform_track_insert_key(animtrack, 0.0, Vector3.ZERO, Quat.IDENTITY, Vector3.ONE)
			anim.transform_track_insert_key(animtrack, getprop(vertdown, "xRange") / 90.0, Vector3.ZERO, Basis(Vector3(1,0,0), -getprop(vertdown, "yRange") * 3.14159/180.0).get_rotation_quat(), Vector3.ONE)
	return animplayer


func _parse_secondary_node(secondary_node: Node, vrm_extension: Dictionary, gstate: GLTFState):
	var nodes = gstate.get_nodes()
	var skeletons = gstate.get_skeletons()

	var vrm_secondary:GDScript = load("res://addons/vrm/vrm_secondary.gd")
	var vrm_collidergroup:GDScript = load("res://addons/vrm/vrm_collidergroup.gd")
	var vrm_springbone:GDScript = load("res://addons/vrm/vrm_springbone.gd")

	var collider_groups: Array = []
	for cgroup in getprop(getprop(vrm_extension,"secondaryAnimation"),"colliderGroups"):
		var gltfnode: GLTFNode = nodes[int(getprop(cgroup,"node"))]
		var collider_group = vrm_collidergroup.new()
		collider_group.sphere_colliders = [].duplicate() # HACK HACK HACK
		if gltfnode.skeleton == -1:
			var found_node: Node = gstate.get_scene_node(int(getprop(cgroup,"node")))
			collider_group.skeleton_or_node = secondary_node.get_path_to(found_node)
			collider_group.bone = ""
			collider_group.resource_name = found_node.name
		else:
			var skeleton: Skeleton3D = _get_skel_godot_node(gstate, nodes, skeletons,gltfnode.skeleton)
			collider_group.skeleton_or_node = secondary_node.get_path_to(skeleton)
			collider_group.bone = nodes[int(getprop(cgroup, "node"))].resource_name
			collider_group.resource_name = collider_group.bone
		
		for collider_info in getprop(cgroup, "colliders"):
			var offset_obj = collider_info.get("offset", {"x": 0.0, "y": 0.0, "z": 0.0})
			var local_pos: Vector3 = Vector3(getprop(offset_obj,"x"), getprop(offset_obj,"y"), getprop(offset_obj,"z"))
			var radius: float = collider_info.get("radius", 0.0)
			collider_group.sphere_colliders.append(Plane(local_pos, radius))
		collider_groups.append(collider_group)

	var spring_bones: Array = []
	for sbone in getprop(getprop(vrm_extension,"secondaryAnimation"),"boneGroups"):
		if getpropdef(sbone, "bones", []).size() == 0:
			continue
		var first_bone_node: int = getprop(sbone, "bones")[0]
		var gltfnode: GLTFNode = nodes[int(first_bone_node)]
		var skeleton: Skeleton3D = _get_skel_godot_node(gstate, nodes, skeletons,gltfnode.skeleton)

		var spring_bone = vrm_springbone.new()
		spring_bone.skeleton = secondary_node.get_path_to(skeleton)
		spring_bone.comment = getpropdef(sbone, "comment", "")
		spring_bone.stiffness_force = float(getpropdef(sbone, "stiffiness", 1.0))
		spring_bone.gravity_power = float(getpropdef(sbone, "gravityPower", 0.0))
		var gravity_dir = getpropdef(sbone, "gravity_dir", {"x": 0.0, "y": -1.0, "z": 0.0})
		spring_bone.gravity_dir = Vector3(getprop(gravity_dir,"x"), getprop(gravity_dir,"y"), getprop(gravity_dir,"z"))
		spring_bone.drag_force = float(getpropdef(sbone, "drag_force", 0.4))
		spring_bone.hit_radius = float(getpropdef(sbone, "hitRadius", 0.02))
		
		if spring_bone.comment != "":
			spring_bone.resource_name = spring_bone.comment.split("\n")[0]
		else:
			var tmpname: String = ""
			if getprop(sbone, "bones").size() > 1:
				tmpname += " + " + str(getprop(sbone, "bones").size() - 1) + " roots"
			tmpname = nodes[int(first_bone_node)].resource_name + tmpname
			spring_bone.resource_name = tmpname
		
		spring_bone.collider_groups = [].duplicate() # HACK HACK HACK
		for cgroup_idx in getpropdef(sbone, "colliderGroups", []):
			spring_bone.collider_groups.append(collider_groups[int(cgroup_idx)])

		spring_bone.root_bones = [].duplicate() # HACK HACK HACK
		for bone_node in getprop(sbone, "bones"):
			var bone_name:String = nodes[int(bone_node)].resource_name
			if skeleton.find_bone(bone_name) == -1:
				# Note that we make an assumption that a given SpringBone object is
				# only part of a single Skeleton*. This error might print if a given
				# SpringBone references bones from multiple Skeleton's.
				printerr("Failed to find node " + str(bone_node) + " in skel " + str(skeleton))
			else:
				spring_bone.root_bones.append(bone_name)

		# Center commonly points outside of the glTF Skeleton, such as the root node.
		spring_bone.center_node = secondary_node.get_path_to(secondary_node)
		spring_bone.center_bone = ""
		var center_node_idx = getpropdef(sbone, "center", -1)
		if center_node_idx != -1:
			var center_gltfnode: GLTFNode = nodes[int(center_node_idx)]
			var bone_name:String = center_gltfnode.resource_name
			if center_gltfnode.skeleton == gltfnode.skeleton and skeleton.find_bone(bone_name) != -1:
				spring_bone.center_bone = bone_name
				spring_bone.center_node = NodePath()
			else:
				spring_bone.center_bone = ""
				spring_bone.center_node = secondary_node.get_path_to(gstate.get_scene_node(int(center_node_idx)))
				if spring_bone.center_node == NodePath():
					printerr("Failed to find center scene node " + str(center_node_idx))
					spring_bone.center_node = secondary_node.get_path_to(secondary_node) # Fallback

		spring_bones.append(spring_bone)

	secondary_node.set_script(vrm_secondary)
	secondary_node.set("spring_bones", spring_bones)
	secondary_node.set("collider_groups", collider_groups)
	# If [] is replaced with Array() above, godot crashes (cyclic references??)


func _import_scene(path: String, flags: int, bake_fps: int):
	var f = File.new()
	if f.open(path, File.READ) != OK:
		return FAILED

	var magic = f.get_32()
	if magic != 0x46546C67:
		return ERR_FILE_UNRECOGNIZED
	f.get_32() # version
	f.get_32() # length

	var chunk_length = f.get_32();
	var chunk_type = f.get_32();

	if chunk_type != 0x4E4F534A:
		return ERR_PARSE_ERROR
	var json_data : PackedByteArray = f.get_buffer(chunk_length)
	f.close()

	var gstate : GLTFState = GLTFState.new()
	var gltf : PackedSceneGLTF = PackedSceneGLTF.new()
	print(path);
	var root_node : Node = gltf.import_gltf_scene(path, 0, 1000.0, gstate)
	var gltf_json : Dictionary = gstate.json
	if hasprop(gltf_json, "extensions") == false:
		return null
	var vrm_extension : Dictionary = getprop(getprop(gltf_json, "extensions"), "VRM")

	var human_bone_to_idx: Dictionary = {}
	# Ignoring in ["humanoid"]: armStretch, legStretch, upperArmTwist
	# lowerArmTwist, upperLegTwist, lowerLegTwist, feetSpacing,
	# and hasTranslationDoF
	for human_bone in getprop(getprop(vrm_extension,"humanoid"),"humanBones"):
		human_bone_to_idx[getprop(human_bone,"bone")] = int(getprop(human_bone,"node"))
		# Unity Mecanim properties:
		# Ignoring: useDefaultValues
		# Ignoring: min
		# Ignoring: max
		# Ignoring: center
		# Ingoring: axisLength

	_update_materials(vrm_extension, gstate)

	var animplayer = AnimationPlayer.new()
	animplayer.name = "anim"
	root_node.add_child(animplayer)
	animplayer.owner = root_node
	_create_animation_player(animplayer, vrm_extension, gstate, human_bone_to_idx)

	var vrm_top_level:GDScript = load("res://addons/vrm/vrm_toplevel.gd")
	root_node.set_script(vrm_top_level)

	var vrm_meta: Resource = _create_meta(root_node, animplayer, vrm_extension, gstate, human_bone_to_idx)
	root_node.set("vrm_meta", vrm_meta)
	root_node.set("vrm_secondary", NodePath())
	var secondary_path: NodePath = NodePath()

	if (hasprop(vrm_extension,"secondaryAnimation") and \
			(getpropdef(getprop(vrm_extension,"secondaryAnimation"), "colliderGroups", []).size() > 0 or \
			getpropdef(getprop(vrm_extension,"secondaryAnimation"), "boneGroups", []).size() > 0)):

		var secondary_node: Node = root_node.get_node("secondary")
		if secondary_node == null:
			secondary_node = Node3D.new()
			root_node.add_child(secondary_node)
			secondary_node.set_owner(root_node)
		
		secondary_path = root_node.get_path_to(secondary_node)
		root_node.set("vrm_secondary", secondary_path)

		_parse_secondary_node(secondary_node, vrm_extension, gstate)


	if ResourceLoader.exists(path + ".res") == false:
		ResourceSaver.save(path + ".res", gstate)
	# Remove references
	var packed_scene: PackedScene = PackedScene.new()
	# Nothing seems to be working. scripts on root node get deleted?
	root_node.get_child(0).set_script(vrm_top_level.duplicate())
	root_node.get_child(0).set("vrm_meta", vrm_meta.duplicate())
	root_node.get_child(0).set("vrm_secondary", NodePath("../" + str(secondary_path)))
	root_node.get_child(0).set("vrm_skeleton", NodePath("../" + str(root_node.get("vrm_skeleton"))))
	root_node.get_child(0).set("vrm_animplayer", NodePath("../" + str(root_node.get("vrm_animplayer"))))
	root_node.set_script(vrm_top_level)
	root_node.set("vrm_meta", vrm_meta)
	root_node.set("vrm_secondary", secondary_path)
	packed_scene.set_script(vrm_top_level.duplicate())
	packed_scene.set("vrm_meta", vrm_meta.duplicate())
	packed_scene.set("vrm_secondary", secondary_path)
	packed_scene.pack(root_node)
	packed_scene.set_script(vrm_top_level.duplicate())
	packed_scene.set("vrm_meta", vrm_meta.duplicate())
	packed_scene.set("vrm_secondary", secondary_path)
	var pi = packed_scene.instance(PackedScene.GEN_EDIT_STATE_INSTANCE)
	pi.set_script(vrm_top_level.duplicate())
	pi.set("vrm_meta", vrm_meta.duplicate())
	pi.set("vrm_secondary", secondary_path)
	return pi

func import_animation_from_other_importer(path: String, flags: int, bake_fps: int):
	return self._import_animation(path, flags, bake_fps)


func import_scene_from_other_importer(path: String, flags: int, bake_fps: int):
	return self._import_scene(path, flags, bake_fps)

func _convert_sql_to_material_param(column_name: String, value):
	if "color" in column_name:
		pass
	return value

func _to_dict(columns: Array, values: Array):
	var dict : Dictionary = {}
	for i in range(columns.size()):
		dict[columns[i]] = values[i]
	return dict

func _to_material_param_dict(columns: Array, values: Array):
	var dict : Dictionary = {}
	print("Col size=" + str(columns.size()) + " val size=" + str(values.size()))
	for i in range(min(columns.size(), values.size())):
		dict[columns[i]] = _convert_sql_to_material_param(columns[i], values[i])
	return dict
