@tool
extends EditorPlugin

var menu_item
var current_scene

func _enter_tree():
	# Controlla se il plugin è abilitato all'avvio
	current_scene = EditorInterface.get_edited_scene_root()
	print("Current Scene:", current_scene)
	if EditorInterface.is_plugin_enabled("res://addons/gdspy/plugin.cfg"):
		_enable_plugin()

func _enable_plugin():
	if menu_item == null:
		menu_item = MenuButton.new()
		menu_item.text = "Import fSpy"
		menu_item.pressed.connect(_on_import_fspy_pressed)
		add_control_to_container(EditorPlugin.CONTAINER_TOOLBAR, menu_item)

func _disable_plugin():
	remove_control_from_container(EditorPlugin.CONTAINER_TOOLBAR, menu_item)
	menu_item = null

func _on_import_fspy_pressed():
	#var node = Node3D.new()
	#current_scene.add_child(node)
	#node.owner = current_scene
	#print("Current Scene:", current_scene)
	#print("Added Node:", node)
	#print(current_scene.get_children())
	# Apre il file dialog per selezionare un file fSpy
	var file_dialog = FileDialog.new()
	file_dialog.title = "Apri progetto fSpy"
	file_dialog.mode = FileDialog.FILE_MODE_OPEN_FILE
	file_dialog.access = FileDialog.ACCESS_FILESYSTEM
	file_dialog.filters = ["*.fspy"]
	file_dialog.file_selected.connect(_import_fspy_file)
	get_tree().get_root().add_child(file_dialog)  # Aggiungi il dialogo all'albero
	file_dialog.popup_centered()

func _import_fspy_file(path):
	# Chiamata alla funzione di importazione per il file selezionato
	print("Importa il file fSpy: ", path)
	# Aggiungi qui la logica per importare la telecamera e l'immagine
	import_fspy(path)

func import_fspy(filepath: String) -> void:
	var file = FileAccess.open(filepath, FileAccess.READ)
	var buffer = file.get_buffer(4)
	var file_id = buffer[0] | (buffer[1] << 8) | (buffer[2] << 16) | (buffer[3] << 24)
	if file == null:
		push_error("Impossibile aprire il file fSpy.")
		return
	
	# Verifica dell'identificatore del file
	if file_id != 2037412710:
		push_error("Il file non è un progetto fSpy valido.")
		file.close()
		return
	
	# Lettura della versione del progetto
	var project_version = file.get_32()
	if project_version != 1:
		push_error("Versione del progetto fSpy non supportata.")
		file.close()
		return
	
	# Lettura delle dimensioni della stringa JSON e del buffer immagine
	var state_string_size = file.get_32()
	var image_buffer_size = file.get_32()
	
	# Lettura della stringa JSON
	file.seek(16)  # Salta i primi 16 byte
	var json_string = file.get_buffer(state_string_size).get_string_from_utf8()
	var state = JSON.parse_string(json_string)
	if state.has("error") and state["error"] != OK:
		push_error("Errore nel parsing della stringa JSON.")
		file.close()
		return
	
	# Estrazione dei parametri della telecamera
	var camera_params = state["cameraParameters"]
	var principal_point = Vector2(camera_params["principalPoint"]["x"], camera_params["principalPoint"]["y"])
	var fov_horiz = camera_params["horizontalFieldOfView"]
	var camera_transform = camera_params["cameraTransform"]["rows"]
	var image_width = camera_params["imageWidth"]
	var image_height = camera_params["imageHeight"]
	
	# Lettura dell'immagine
	var image_data = file.get_buffer(image_buffer_size)
	file.close()
	
	# Creazione della telecamera in scena
	_create_camera(fov_horiz, camera_transform, principal_point, image_width, image_height, image_data)

func _create_camera(fov_horiz: float, camera_transform: Array, principal_point: Vector2, image_width: int, image_height: int, image_data: PackedByteArray) -> void:
	var camera = Camera3D.new()
	camera.name = "fSpy Camera"
	# Converti da radianti a gradi
	var fov_horiz_degrees = fov_horiz * (180.0 / PI)
	# Verifica il valore del FOV
	if fov_horiz_degrees < 1.0 or fov_horiz_degrees > 179.0:
		push_error("FOV non valido: " + str(fov_horiz))
		return
	camera.fov = fov_horiz_degrees
	camera.set_projection(Camera3D.PROJECTION_PERSPECTIVE)
	current_scene.add_child(camera)
	camera.owner = current_scene
	var transform = Transform3D()
	# Assicurati che camera_transform abbia la dimensione corretta
	for i in range(3):  # Solo 0, 1, 2 per la parte 3x3
		for j in range(3):  # Assumi che camera_transform abbia 4 colonne
			transform.basis[i][j] = camera_transform[i][j]
	# Scambia l'asse X con l'asse Z per adattarlo a Godot
	#var temp = transform.basis[0]  # Salva la colonna X
	#transform.basis[0] = transform.basis[2]  # Z diventa X
	#transform.basis[2] = temp  # X diventa Z
	camera.transform = transform
	camera.rotation_edit_mode = Node3D.ROTATION_EDIT_MODE_QUATERNION
	camera.quaternion.z *= -1 
	camera.scale.y = -1
	
	# Configurazione del background con l'immagine importata
	var image = Image.new()
	var success = image.load_jpg_from_buffer(image_data)
	print("Lunghezza dei dati immagine:", image_data.size())
	if success != OK:
		push_error("Errore nel caricamento dell'immagine JPG.")
		return
	var save_path = "user://loaded_image.jpg"
	if image.save_jpg(save_path) == OK:
		print("Immagine salvata con successo:", save_path)
	else:
		push_error("Errore nel salvataggio dell'immagine.")
	
	var loaded_img = Image.new()
	var error = loaded_img.load(save_path)
	print("Larghezza immagine salvata:", loaded_img.get_width(), "Altezza immagine salvata:", loaded_img.get_height())
	if error == OK:
		print("nessun errore di caricamento")
	var canvas_layer = CanvasLayer.new()
	current_scene.add_child(canvas_layer)
	canvas_layer.owner = current_scene
	var texture_rect = TextureRect.new()
	var image_texture = ImageTexture.new()
	image_texture = image_texture.create_from_image(loaded_img)
	texture_rect.texture = image_texture
	texture_rect.queue_redraw()
	#exture_rect.rect_min_size = Vector2(1920, 1080)  # Imposta la dimensione secondo le tue necessità
	canvas_layer.add_child(texture_rect)
	texture_rect.owner = current_scene
	#Questo serve ad impostare la trasparenza del immagine nel 
	var col = Color(1,1,1,0.5)
	texture_rect.set_modulate(col)

	# Impostazione della risoluzione di rendering
	var viewport = get_viewport()
	viewport.size = Vector2(image_width, image_height)
	ProjectSettings.set_setting("display/window/size/viewport_height", image_height)
	ProjectSettings.set_setting("display/window/size/viewport_widht", image_width)

	# Imposta lo shift della telecamera per allineare il punto principale
	var x_shift_scale = 1.0
	var y_shift_scale = 1.0
	if image_height > image_width:
		x_shift_scale = float(image_width) / image_height
	else:
		y_shift_scale = float(image_height) / image_width
	
	camera.h_offset = x_shift_scale * (0.5 - principal_point.x)
	camera.v_offset = y_shift_scale * (0.5 - principal_point.y)
	
	print("Importazione del file fSpy completata.")
