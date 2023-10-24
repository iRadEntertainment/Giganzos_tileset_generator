extends Control

const TILE_SIZE = Vector2i(128, 128)
const SRC_RECT = Rect2i(Vector2i(), TILE_SIZE)
const format = Image.FORMAT_RGBA8

enum P{NW, N, NE, W, C, E, SW, S, SE}
var peer := [
	Vector2i(-1,-1), Vector2i( 0,-1), Vector2i( 1,-1),
	Vector2i(-1, 0), Vector2i( 0, 0), Vector2i( 1, 0),
	Vector2i(-1, 1), Vector2i( 0, 1), Vector2i( 1, 1),
	]

var tileset : TileSet
var tileset_source : TileSetAtlasSource
@export var peer_bit_color : Color

enum Selecting{TILE, MASK, MASK_CORNER, BG}
var selecting : int
@onready var filediag = %filediag as FileDialog
@onready var peer_bits_ref = %peer_bits_ref
@onready var tile_prev = %tile_preview
@onready var mask_prev = %mask_preview
@onready var mask_corner_prev = %mask_corner_preview
@onready var bg_prev = %bg_preview
@onready var spritesheet_prew = %spritesheet_preview

var peering_bits_ref_img : Image
var spritesheet_grid_size := Vector2i()
var cell_pack := preload("res://instances/bit_cell.tscn")
var cells_array = []

var tile_base_img : Image
var tile_bg_img : Image

var mask_straight_img : Image # given by the texture

var mask_diag_img : Image # given by the texture
var mask_diag2_img : Image # a quarter of the previous one
var mask_bend_img : Image # mask for straight-to-diagonal bends
var mask_bend_mirror_img : Image # mask for straight-to-diagonal bends
var mask_trapezoid_img : Image # mask for small outside road triangles
var mask_straight_diag_img : Image # mask for the straight roads that go diagonally
var mask_end_diag_img : Image # mask for the end roads that go diagonally

var mask_corner_in_img : Image # create a small square mask from two straight masks
var mask_corner_in_diag_img : Image # create a small triangle (small square + scaled down diag mask)
var mask_vshape_img : Image # create a small triangle (small square + scaled down diag mask)
var mask_vshape_fill_img : Image # create a small triangle (small square + scaled down diag mask)

var result_img : Image
var result_size : Vector2i

enum Dir{N, W, S, E, NW, SW, SE, NE}




#=================================== INIT ======================================

var is_ready := false
func _ready():
	is_ready = true
	
	get_peer_bits_from_ref_image()
	get_base_tile()
	get_mask_straight()
	get_mask_diag()
	get_bg()
	call_deferred("update_tilesheet", cells_array)


func get_peer_bits_from_ref_image():
	peering_bits_ref_img = peer_bits_ref.texture.get_image()
	spritesheet_grid_size = peering_bits_ref_img.get_size()
	assert(spritesheet_grid_size.x%3 == 0, "the dimension of the reference image should be divisibel by 3")
	assert(spritesheet_grid_size.y%3 == 0, "the dimension of the reference image should be divisibel by 3")
	spritesheet_grid_size /= 3
	
	result_size = spritesheet_grid_size * TILE_SIZE
	result_img = Image.create(result_size.x, result_size.y, true, format)
	spritesheet_prew.texture = ImageTexture.create_from_image(result_img)
#	spritesheet_prew.size.y = spritesheet_prew.size.x * (float(spritesheet_grid_size.y) / float(spritesheet_grid_size.x))
	
	%peer_bits.columns = spritesheet_grid_size.x
	for c in %peer_bits.get_children():
		c.queue_free()
	
	cells_array.clear()
	for y in spritesheet_grid_size.y:
		for x in spritesheet_grid_size.x:
			var new_c = cell_pack.instantiate(PackedScene.GEN_EDIT_STATE_INSTANCE)
			var p = Vector2i(x,y)
			new_c.grid_pos = p
			new_c.bit_set.connect(_on_bit_set)
			new_c.active_bits = get_active_bits_from_img(p)
			%peer_bits.add_child(new_c)
			cells_array.append(new_c)


func get_active_bits_from_img(p : Vector2i) -> Array[bool]:
	var active_bits : Array[bool] = []
	peering_bits_ref_img
	for y in 3:
		for x in 3:
			var off = Vector2i(x,y)
			var px_pos = p*3 + off
			var col = peering_bits_ref_img.get_pixelv(px_pos)
			active_bits.append( col != Color.WHITE )
	return active_bits


func get_base_tile():
	tile_base_img = tile_prev.texture.get_image()
	tile_base_img.convert(format)
func get_mask_straight():
	mask_straight_img = mask_prev.texture.get_image()
	mask_straight_img.convert(format)
	create_additional_masks()
func get_mask_diag():
	mask_diag_img = mask_corner_prev.texture.get_image()
	mask_diag_img.convert(format)
	create_additional_masks()
func get_bg():
	tile_bg_img = bg_prev.texture.get_image()
	tile_bg_img.convert(format)


# =============================== GENERATE =====================================
func update_tilesheet(cells : Array):
	for c in cells:
		var bits = c.active_bits
		
		var edge_dir = []
		if !bits[P.NW] and !bits[P.N ] and !bits[P.NE]:
			edge_dir.append(Dir.N)
		if !bits[P.NE] and !bits[P.E ] and !bits[P.SE]:
			edge_dir.append(Dir.E)
		if !bits[P.SW] and !bits[P.S ] and !bits[P.SE]:
			edge_dir.append(Dir.S)
		if !bits[P.NW] and !bits[P.W ] and !bits[P.SW]:
			edge_dir.append(Dir.W)
		
		var corner_dir = []
		if !bits[P.NW]: corner_dir.append(Dir.NW)
		if !bits[P.NE]: corner_dir.append(Dir.NE)
		if !bits[P.SE]: corner_dir.append(Dir.SE)
		if !bits[P.SW]: corner_dir.append(Dir.SW)
		
		var tile_img := tile_base_img.duplicate()
		for dir in edge_dir:
			var mask = get_rotated_mask(mask_straight_img, dir)
			tile_img = apply_mask(tile_img, mask)
		for dir in corner_dir:
			var mask = get_rotated_mask(mask_corner_in_img, dir)
			tile_img = apply_mask(tile_img, mask)
		
		var tile_and_bg_img = tile_bg_img.duplicate() as Image
		tile_and_bg_img.blend_rect(tile_img, SRC_RECT, Vector2i() )
		result_img.blit_rect(tile_and_bg_img, SRC_RECT, c.grid_pos * TILE_SIZE)
	
	spritesheet_prew.size.y = spritesheet_prew.size.x * (float(spritesheet_grid_size.y) / float(spritesheet_grid_size.x))
	spritesheet_prew.texture = ImageTexture.create_from_image(result_img)


func generate_tileset_resource():
	tileset = TileSet.new() as TileSet
	tileset.tile_size = TILE_SIZE
	tileset.add_terrain_set(0)
	tileset.add_terrain(0, 0)
	
	tileset_source = TileSetAtlasSource.new()
	tileset_source.texture = %spritesheet_preview.texture
	tileset_source.texture_region_size = TILE_SIZE
	
	for cell in cells_array:
		var p = cell.grid_pos
		tileset_source.create_tile(p)
		var tile_data = tileset_source.get_tile_data(p, 0) as TileData
		tile_data.terrain_set = 0
		
		var peer_bits = []
		for j in cell.active_bits.size():
			var bit = cell.active_bits[j]
			if bit: peer_bits.append(j)
		
		if P.C in peer_bits:
			tile_data.terrain = 0
		
		for peer_bit in peer_bits:
			if peer_bit == P.C: continue
			tile_data.set_terrain_peering_bit(map_bit_to_const(peer_bit), 0)
	
	tileset.add_source(tileset_source, 0)


func map_bit_to_const(peer_bit : P):
	match peer_bit:
		P.NW: return TileSet.CELL_NEIGHBOR_TOP_LEFT_CORNER
		P.N : return TileSet.CELL_NEIGHBOR_TOP_SIDE
		P.NE: return TileSet.CELL_NEIGHBOR_TOP_RIGHT_CORNER
		P.W : return TileSet.CELL_NEIGHBOR_LEFT_SIDE
		P.E : return TileSet.CELL_NEIGHBOR_RIGHT_SIDE
		P.SW: return TileSet.CELL_NEIGHBOR_BOTTOM_LEFT_CORNER
		P.S : return TileSet.CELL_NEIGHBOR_BOTTOM_SIDE
		P.SE: return TileSet.CELL_NEIGHBOR_BOTTOM_RIGHT_CORNER


#================================= MASKS GEN ==================================
func create_additional_masks():
	if !mask_straight_img or !mask_diag_img:
		return
	mask_diag2_img = mask_diag_img.duplicate()
	mask_diag2_img.resize(TILE_SIZE.x/2, TILE_SIZE.y/2)
	mask_corner_in_img = create_inner_corner()
	mask_corner_in_diag_img = create_inner_corner_diag()
	mask_bend_img = create_bend_mask()
	mask_bend_mirror_img = mask_bend_img.duplicate()
	mask_bend_mirror_img.flip_x()
	mask_bend_mirror_img.rotate_90(COUNTERCLOCKWISE)
	
	mask_trapezoid_img = create_trapezoid_mask()
	mask_straight_diag_img = create_straight_diag_mask()
	mask_end_diag_img = create_end_diag_mask()
	
	mask_vshape_img = create_vshape_mask()
	mask_vshape_fill_img = create_vshape_fill_mask()
	
	# preview the masks in the panel
	for child in %flow.get_children():
		child.queue_free()
	for mask in [
				mask_diag2_img, mask_corner_in_img, mask_corner_in_diag_img,
				mask_bend_img, mask_bend_mirror_img, mask_trapezoid_img,
				mask_straight_diag_img, mask_end_diag_img, mask_vshape_img, mask_vshape_fill_img
			]:
		var tex_rect = TextureRect.new()
		tex_rect.texture = ImageTexture.create_from_image(mask)
		tex_rect.stretch_mode = TextureRect.STRETCH_KEEP_CENTERED
		%flow.add_child(tex_rect)


func create_inner_corner() -> Image:
	var img = mask_straight_img.duplicate()
	var rot = mask_straight_img.duplicate()
	rot.rotate_90(COUNTERCLOCKWISE)
	return screen_masks(img, rot)


func create_inner_corner_diag() -> Image:
	var img = Image.create(TILE_SIZE.x, TILE_SIZE.y, true, format)
	img.fill(Color.WHITE)
	var img_b = mask_diag_img.duplicate()
	img_b.resize(TILE_SIZE.x/8, TILE_SIZE.y/8)
	img.blit_rect(img_b, Rect2i(Vector2i(), TILE_SIZE/8), Vector2i())
	return img


func create_bend_mask() -> Image:
	var img = mask_straight_img.duplicate()
	img.rotate_90(CLOCKWISE)
	var diag_add = mask_diag_img.duplicate()
	diag_add.rotate_180()
	diag_add.blit_rect(diag_add, SRC_RECT, Vector2i(TILE_SIZE.x/2, 0) )
	
	img = screen_masks(img, diag_add)
	var straight_left = mask_straight_img.duplicate()
	straight_left.rotate_90(COUNTERCLOCKWISE)
	img = mult_masks(img, straight_left)
	img = mult_masks(img, mask_diag2_img)
	
	return img


func create_trapezoid_mask() -> Image:
	var img = Image.create(TILE_SIZE.x, TILE_SIZE.y, true, format)
	img.fill(Color.BLACK)
	img.blit_rect(mask_diag2_img, Rect2i(Vector2i(), mask_diag2_img.get_size()), TILE_SIZE/2)
	return img


func create_straight_diag_mask() -> Image:
	var img = Image.create(TILE_SIZE.x, TILE_SIZE.y, true, format)
	img.fill(Color.WHITE)
	img.blit_rect(mask_diag2_img, Rect2i(Vector2i(), mask_diag2_img.get_size()), Vector2i())
	var rot = mask_diag2_img.duplicate() as Image
	rot.rotate_180()
	img.blit_rect(rot, Rect2i(Vector2i(), rot.get_size()), TILE_SIZE/2)
	
	return img


func create_end_diag_mask() -> Image:
	var img = mask_straight_diag_img.duplicate()
	img.rotate_90(CLOCKWISE)
	img = mult_masks(img, mask_straight_img)
	var rot = mask_straight_img.duplicate() as Image
	rot.rotate_90(COUNTERCLOCKWISE)
	img = mult_masks(img, rot)
	return img


func create_vshape_mask() -> Image:
	var img = mask_straight_img.duplicate()
	img = mult_masks(img, mask_diag2_img)
	var rot = mask_diag2_img.duplicate() as Image
	rot.rotate_90(CLOCKWISE)
	img.blit_rect(rot, Rect2i(Vector2i(), rot.get_size()), Vector2i(TILE_SIZE.x/2, 0))
	img = mult_masks(img, mask_straight_img)
	return img


func create_vshape_fill_mask() -> Image:
	var img = Image.create(TILE_SIZE.x, TILE_SIZE.y, true, format)
	img.fill(Color.BLACK)
	img.blit_rect(mask_diag2_img, Rect2i(Vector2i(), mask_diag2_img.get_size()), TILE_SIZE/2)
	var rot = mask_diag2_img.duplicate() as Image
	rot.rotate_90(CLOCKWISE)
	img.blit_rect(rot, Rect2i(Vector2i(), rot.get_size()), Vector2i(0, TILE_SIZE.y/2))
	
	return img


func apply_mask(img : Image, mask : Image) -> Image:
	for x in TILE_SIZE.x:
		for y in TILE_SIZE.y:
			var col = img.get_pixel(x, y)
			col.a = min( col.a, mask.get_pixel(x, y).r )
			img.set_pixel(x, y, col)
	return img


#================================ GET MASKS ====================================
func get_rotated_mask(mask : Image, edge_dir : Dir) -> Image:
	var rotated_mask := mask.duplicate() as Image
	match edge_dir:
		Dir.N: pass
		Dir.W: rotated_mask.rotate_90(COUNTERCLOCKWISE)
		Dir.S: rotated_mask.rotate_180()
		Dir.E: rotated_mask.rotate_90(CLOCKWISE)
		Dir.NW: pass
		Dir.SW: rotated_mask.rotate_90(COUNTERCLOCKWISE)
		Dir.SE: rotated_mask.rotate_180()
		Dir.NE: rotated_mask.rotate_90(CLOCKWISE)
	return rotated_mask



#============================= PREVIEW PAN/ZOOM ================================
func _on_cnt_gui_input(event):
	if event is InputEventMouseButton:
		if event.is_pressed():
			if event.button_index == MOUSE_BUTTON_WHEEL_UP:
				spritesheet_prew.scale *= 1.1
			elif event.button_index == MOUSE_BUTTON_WHEEL_DOWN:
				spritesheet_prew.scale /= 1.1
	
	if event is InputEventMouseMotion:
		if Input.is_mouse_button_pressed(MOUSE_BUTTON_MIDDLE):
			spritesheet_prew.position += event.relative


#================================== UTILS ======================================
func screen_masks(mask_1 : Image, mask_2 : Image) -> Image:
	var min_size := Vector2i()
	min_size.x = min(mask_1.get_size().x, mask_2.get_size().x)
	min_size.y = min(mask_1.get_size().y, mask_2.get_size().y)
	
	var new_mask = mask_1.duplicate() as Image
	for x in min_size.x:
		for y in min_size.y:
			var a = mask_1.get_pixel(x, y).r
			var b = mask_2.get_pixel(x, y).r
			var max_red_val = max(a, b)
			var col = Color(max_red_val, max_red_val, max_red_val)
			new_mask.set_pixel(x, y, col)
	
	return new_mask


func mult_masks(mask_1 : Image, mask_2 : Image) -> Image:
	var min_size := Vector2i()
	min_size.x = min(mask_1.get_size().x, mask_2.get_size().x)
	min_size.y = min(mask_1.get_size().y, mask_2.get_size().y)
	
	var new_mask = mask_1.duplicate() as Image
	for x in min_size.x:
		for y in min_size.y:
			var a = mask_1.get_pixel(x, y).r
			var b = mask_2.get_pixel(x, y).r
			var mult_red_val = a * b
			var col = Color(mult_red_val, mult_red_val, mult_red_val)
			new_mask.set_pixel(x, y, col)
	
	return new_mask


#================================= SIGNALS =====================================
func _on_filediag_file_selected(path):
	match selecting:
		Selecting.TILE:
			tile_prev.texture = load(path)
			tile_base_img = tile_prev.texture.get_image()
			tile_base_img.convert(format)
		Selecting.MASK:
			mask_prev.texture = load(path)
			mask_straight_img = mask_prev.texture.get_image()
			mask_straight_img.convert(format)
		Selecting.MASK_CORNER:
			mask_corner_prev.texture = load(path)
			mask_diag_img = mask_corner_prev.texture.get_image()
			mask_diag_img.convert(format)
		Selecting.BG:
			bg_prev.texture = load(path)
			tile_bg_img = bg_prev.texture.get_image()
			tile_bg_img.convert(format)
	
	create_additional_masks()
	update_tilesheet(cells_array)


func _on_bit_set(cell_id, cell_active_bits, cell_grid_pos):
	update_tilesheet( [%peer_bits.get_child(cell_id)] )

func _on_btn_tile_select_pressed():
	filediag.popup(%cnt_prev.get_rect())
	selecting = Selecting.TILE
func _on_btn_mask_select_pressed():
	filediag.popup(%cnt_prev.get_rect())
	selecting = Selecting.MASK
func _on_btn_mask_corner_pressed():
	filediag.popup(%cnt_prev.get_rect())
	selecting = Selecting.MASK_CORNER
func _on_btn_bg_pressed():
	filediag.popup(%cnt_prev.get_rect())
	selecting = Selecting.BG


# ============================ SAVE TO FILE ====================================
func _on_btn_save_tex_pressed():
	%filediag_save_tex.popup(%cnt_prev.get_rect())
func _on_filediag_save_tex_file_selected(path):
	var tex = spritesheet_prew.texture
	var img = tex.get_image()
	img.save_png(path)
func _on_btn_save_tileset_pressed():
	%filediag_save_tileset.popup(%cnt_prev.get_rect())
func _on_filediag_save_tileset_file_selected(path):
	generate_tileset_resource()
	ResourceSaver.save(tileset, path)



















