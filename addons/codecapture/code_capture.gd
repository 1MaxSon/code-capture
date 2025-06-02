@tool
extends EditorPlugin

 
const EDITOR_FONT_DIR = "editor_font"
const CAPTURE_MENU_BUTTON = preload("./capture_menu_button.tscn")
const ID_CAPTURE_ITEM := 0
const ID_CAPTURE_SEL_ITEM := 1
const ID_SHOW_GODOT_VER := 3
const ID_EXPAND_SEL_TO_FULL := 4
const ID_APPEND_EMPTY_LINE := 5
var capture_menu_button: MenuButton
var capture_menu_popup: PopupMenu

var script_editor: ScriptEditor
var script_editor_toolbar: HBoxContainer
var editor_filesystem: EditorFileSystem
var code_edit: CodeEdit
var editor_font: Font
var script_path: String
var last_save_path: String = ""


func _enter_tree() -> void:
	editor_filesystem = EditorInterface.get_resource_filesystem()
	if editor_filesystem.is_scanning():
		await editor_filesystem.filesystem_changed
	
	script_path = (get_script() as Script).resource_path
	var font_path := get_first_font_in_dir(script_path.get_base_dir().path_join(EDITOR_FONT_DIR))
	
	if !font_path:
		font_path = await  copy_editor_font_to_project()
	
	if font_path:
		editor_font = load(font_path)
	
	script_editor = EditorInterface.get_script_editor()
	
	script_editor_toolbar = script_editor.get_children()[0].get_children()[0]
	capture_menu_button = CAPTURE_MENU_BUTTON.instantiate()
	script_editor_toolbar.add_child(capture_menu_button)
	capture_menu_button.about_to_popup.connect(_menu_button_about_to_popup)
	
	capture_menu_popup = capture_menu_button.get_popup()
	capture_menu_popup.id_pressed.connect(_on_capture_menu_popup_id_pressed)
	
	var last_index := -1
	for i in script_editor_toolbar.get_child_count():
		var child := script_editor_toolbar.get_child(i)
		if child is MenuButton and child != capture_menu_button:
			last_index = i
	script_editor_toolbar.move_child(capture_menu_button, last_index + 1)


func _exit_tree() -> void:
	editor_font = null
	script_path = ""
	last_save_path = ""
	if capture_menu_button:
		capture_menu_button.queue_free()
		capture_menu_button = null


func _menu_button_about_to_popup() -> void:
	if !code_edit:
		var script_text_editor := script_editor.get_current_editor()
		code_edit = script_text_editor.get_base_editor()
	
	capture_menu_popup.set_item_disabled(ID_CAPTURE_SEL_ITEM, !code_edit.has_selection())


func _on_capture_menu_popup_id_pressed(id: int) -> void:
	if capture_menu_popup.is_item_checkable(id):
		capture_menu_popup.set_item_checked(id, !capture_menu_popup.is_item_checked(id))
		return
	
	var code: String
	match id:
		ID_CAPTURE_ITEM:
			code = script_editor.get_current_script().source_code
		ID_CAPTURE_SEL_ITEM:
			if !code_edit.has_selection():
				push_error("There is no selected code")
				return
			
			if capture_menu_popup.is_item_checked(ID_EXPAND_SEL_TO_FULL):
				var sel_start = code_edit.get_selection_from_line()
				var sel_end = code_edit.get_selection_to_line()
				if sel_start > sel_end:
					var temp = sel_start
					sel_start = sel_end
					sel_end = temp
				
				var lines := code_edit.text.split("\n")
				var selected_lines := lines.slice(sel_start, sel_end + 1)
				code = "\n".join(selected_lines)
			else:
				code = code_edit.get_selected_text()
	
	if capture_menu_popup.is_item_checked(ID_APPEND_EMPTY_LINE):
		if !code.ends_with("\n"):
			code += "\n"
		
		if !code.ends_with("\n\n"):
			code += "\n"
	
	if !code.strip_edges():
		push_error("An empty script!")
		return
	
	capture_code(code)


func copy_editor_font_to_project() -> String:
	var editor_settings := EditorInterface.get_editor_settings()
	var font_path := editor_settings.get_setting("interface/editor/code_font") as String

	if not FileAccess.file_exists(font_path):
		return ""

	var font_bytes := FileAccess.get_file_as_bytes(font_path)
	if font_bytes.size() == 0:
		push_error("The editor font could not be read or it is empty.")
		return ""

	var dir_path := script_path.get_base_dir().path_join(EDITOR_FONT_DIR)
	var dest_path := dir_path.path_join(font_path.get_file())

	if not DirAccess.dir_exists_absolute(dir_path):
		DirAccess.make_dir_recursive_absolute(dir_path)

	var file := FileAccess.open(dest_path, FileAccess.WRITE)
	if file == null:
		push_error("Failed to create a file in: %system" % dest_path)
		return ""

	file.store_buffer(font_bytes)
	file.close()
	
	editor_filesystem.scan()
	if editor_filesystem.is_scanning():
		await editor_filesystem.filesystem_changed
	
	editor_filesystem.update_file(dest_path)
	
	return dest_path


func get_first_font_in_dir(dir_path: String) -> String:
	var dir := DirAccess.open(dir_path)
	if dir == null:
		return ""

	dir.list_dir_begin()
	var file_name = dir.get_next()
	while file_name != "":
		if not dir.current_is_dir():
			return dir_path.path_join(file_name)
		file_name = dir.get_next()

	return ""


func capture_code(code: String) -> void:
	if !code_edit:
		push_error("code_edit not found")
		return

	var code_edit_copy := code_edit.duplicate() as CodeEdit
	code_edit_copy.text = code
	
	if !editor_font:
		editor_font = code_edit.get_theme_default_font()
	
	var version_label: Label
	if capture_menu_button.get_popup().is_item_checked(ID_SHOW_GODOT_VER):
		version_label = Label.new()
		var ver := Engine.get_version_info()
		version_label.text = "Godot v%s [%s]" % [ver["string"], ver["hash"].substr(0, 9)]

		version_label.add_theme_font_override("font", editor_font)
		version_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		version_label.autowrap_mode = TextServer.AUTOWRAP_OFF
		version_label.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		version_label.add_theme_font_size_override(
			"font_size", code_edit.get_theme_font_size("font_size")
		)

	var vbox := VBoxContainer.new()
	vbox.add_theme_constant_override("separation", 0)
	if version_label:
		vbox.add_child(version_label)
	vbox.add_child(code_edit_copy)

	var subviewport := SubViewport.new()
	subviewport.render_target_update_mode = SubViewport.UPDATE_ALWAYS
	subviewport.disable_3d = true
	
	code_edit_copy.add_theme_font_override("font", editor_font)
	code_edit_copy.gutters_draw_bookmarks = false
	code_edit_copy.highlight_current_line = false
	code_edit_copy.scroll_fit_content_height = true
	code_edit_copy.scroll_fit_content_width = true
	
	subviewport.add_child(vbox)
	code_edit_copy.reset_size()
	
	add_child(subviewport)

	call_deferred("make_screenshot", subviewport, code_edit_copy)


func make_screenshot(sv: SubViewport, code_edit: CodeEdit) -> void:
	code_edit.size = Vector2.ZERO
	sv.size = code_edit.size
	
	#code_edit.owner = sv
	#var packed := PackedScene.new()
	#packed.pack(code_edit)
	#ResourceSaver.save(packed, "res://test.tscn")
	
	await RenderingServer.frame_post_draw
	var img := sv.get_texture().get_image()
	
	var dialog := FileDialog.new()
	dialog.access = FileDialog.ACCESS_FILESYSTEM
	dialog.file_mode = FileDialog.FILE_MODE_SAVE_FILE
	
	var current_script := script_editor.get_current_script()
	var script_name := "script"
	if current_script.resource_path != "":
		script_name = current_script.resource_path.get_file() 
	
	if last_save_path != "":
		dialog.current_path = last_save_path
	else:
		dialog.current_path = OS.get_system_dir(
			OS.SYSTEM_DIR_PICTURES
		).path_join(script_name.get_basename() + ".png")


	dialog.filters = PackedStringArray(["*.png", "*.jpg", "*.webp"])
	add_child(dialog)
	dialog.popup_centered()
	
	dialog.file_selected.connect(func(path: String) -> void:
		var save_err: int
		var file_ext := path.get_extension()
		if file_ext == "webp":
			save_err = img.save_webp(path)
		elif file_ext == "jpg":
			save_err = img.save_jpg(path, 0.85)
		else:
			save_err = img.save_png(path)
		last_save_path = path
		if save_err != OK:
			push_error("Couldn't save screenshot. ", error_string(save_err))
		sv.queue_free()
		dialog.queue_free()
	)
	
	dialog.canceled.connect(func() -> void:
		sv.queue_free()
		dialog.queue_free()
	)
