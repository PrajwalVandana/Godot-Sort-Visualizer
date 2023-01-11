extends Control

# TODO: internal code flow is a tangled mess, especialy how we use
#       _running_mode, _is_waiting_for_visualizer and _algo_picker.set_can_continue()

export(NodePath) var _visualizer_path : NodePath

onready var _algo_picker : MarginContainer = $AlgorithmPicker
onready var _continous_timer : Timer = $ContinuousTimer
onready var _visualizer : Control = get_node(_visualizer_path)

var _time_per_step_ms : float = 40 # when continuesly sorting
var _current_sorter = null

enum RunningMode {step, continuous}
var _running_mode : int = RunningMode.step
var _is_waiting_for_visualizer : bool = false

var _settings_file_path : String
var _settings_file : ConfigFile = ConfigFile.new()

func _ready():
	assert(_visualizer_path.is_empty() == false, "assign visualizer scene to main node")
	
	# setup
	_continous_timer.wait_time = _time_per_step_ms / 1000
	
	_visualizer.connect("updated_indexes", self, "_on_visualizer_updated_indexes")
	_visualizer.connect("updated_all", self, "_on_visualizer_updated_all")
	_visualizer.connect("finished", self, "_on_visualizer_finished")
	
	_algo_picker.connect("algorithm_changed", self, "_on_picker_algo_changed")
	_algo_picker.connect("options_changed", self, "_on_picker_options_changed")
	_algo_picker.connect("button_pressed", self, "_on_picker_button_pressed")
	_algo_picker.connect("ui_visibility_changed", self, "_on_picker_ui_visibility_changed")
	
	# create save file if doesn't exist
	var dir : Directory = Directory.new()
	if OS.has_feature("standalone"):
		# TODO: not tested
		_settings_file_path = OS.get_executable_path().get_base_dir() + "/settings"
	else:
		_settings_file_path = "res://settings"
		
	if dir.dir_exists(_settings_file_path) == false:
		dir.make_dir(_settings_file_path)
	
	_settings_file_path += "/settings.cfg"
	if dir.file_exists(_settings_file_path):
		_settings_file.load(_settings_file_path)
		# load from file
		# TODO: config names (like time_per_step) are used twice
		#       once here and once in _on_picker_options_changed, it's prone to errors
		_time_per_step_ms = _settings_file.get_value("settings", "time_per_step", _time_per_step_ms)

func _on_picker_algo_changed(new_sorter):
	_running_mode = RunningMode.step
	_current_sorter = new_sorter
	_reset()

func _on_picker_options_changed(data : Dictionary):
	_time_per_step_ms = data["step_time"]
	_continous_timer.wait_time = _time_per_step_ms / 1000
	
	_settings_file.set_value("settings", "time_per_step", _time_per_step_ms)
	_settings_file.save(_settings_file_path)

func _on_picker_button_pressed(button : String):
	match button:
		"options":
			_algo_picker.show_options_popup({"step_time":_time_per_step_ms})
		"start", "continue":
			_running_mode = RunningMode.continuous
			_continous_timer.start()
		"next":
			_next_step() 
		"pause":
			_running_mode = RunningMode.step
			_continous_timer.stop()
		"stop":
			_running_mode = RunningMode.step
			_reset()
		"last":
			_pause()
			_is_waiting_for_visualizer = true
			_algo_picker.set_can_continue(false)
			_visualizer.update_all(_current_sorter.skip_to_last_step())
		"restart":
			_running_mode = RunningMode.step
			_reset()

func _on_visualizer_updated_indexes():
	_is_waiting_for_visualizer = false
	_algo_picker.set_can_continue(true)
	if _running_mode == RunningMode.continuous && _continous_timer.is_stopped():
		_continous_timer.start()

func _on_visualizer_updated_all():
	_is_waiting_for_visualizer = false
	_algo_picker.set_can_continue(true)
	_visualizer.finish()

func _on_visualizer_finished():
	_algo_picker.sorter_finished()
	_pause()

func _on_picker_ui_visibility_changed(is_visible : bool):
	_visualizer.set_ui_visibility(is_visible)

func _on_continuous_timeout():
	if _is_waiting_for_visualizer == false:
		_next_step()
		_continous_timer.start()

func _next_step():
	var step_data : Dictionary = _current_sorter.next_step()
	assert(step_data.has("done"), "no 'done' entry in sorter.next_step() return")
	
	if step_data["done"]:
		_visualizer.finish()
	else:
		assert(step_data.has("indexes"), "no 'indexes' entry in sorter.next_step() return")
		assert(step_data["indexes"].size() == 2, "'indexes' entry in sorter.next_step() return must have 2 indexes")
		
		_is_waiting_for_visualizer = true
		_algo_picker.set_can_continue(false)
		
		# NOTE: this line should be last in case update_indexes() emits immediately like in visualizer_rect
		_visualizer.update_indexes(step_data["indexes"][0], step_data["indexes"][1])

func _pause():
	if _continous_timer.is_stopped() == false:
		_continous_timer.stop()

func _reset():
	_pause()
	
	_visualizer.reset()
	_is_waiting_for_visualizer = false
	_current_sorter.setup(_visualizer.get_content_count(), funcref(_visualizer, "determine_priority"))
