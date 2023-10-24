# bits_cell
extends GridContainer

var bits_color := Color.RED - Color(0, 0, 0, 0.6)
var active_bits : Array[bool] = []
var id : int = 0
var grid_pos := Vector2i()

signal bit_set

func _ready():
	id = get_index()
#	for bit in active_bits:
	var c_rects = get_children()
	for i in c_rects.size():
		var c = c_rects[i]
		c.gui_input.connect(bit_input.bind(c))
		c.color = bits_color
		c.modulate.a = int(active_bits[i])


func bit_input(event : InputEvent, c_rect : ColorRect):
	if event is InputEventMouseButton:
		if event.is_pressed() and event.button_index == MOUSE_BUTTON_LEFT:
			c_rect.modulate.a = 0 if c_rect.modulate.a == 1 else 1
			active_bits = get_cell_active_bits()
			bit_set.emit(id, active_bits, grid_pos)


func get_cell_active_bits() -> Array[bool]:
	var active_bits : Array[bool] = []
	for c in get_children():
		var bit_active = c.modulate.a == 1
		active_bits.append(bit_active)
	return active_bits







