extends GutTest

const ID := 0
const NAME := 1

var table: LFTable
var host: Control


func before_each():
	host = add_child_autofree(Control.new())
	host.size = Vector2(800, 600)


func after_each():
	# Dropped rows and cells are detached and queue_free()d; let them go.
	await wait_process_frames(1)


func _make_table(show_header := false, show_footer := false) -> LFTable:
	var t := LFTable.new()
	t.header = show_header
	t.footer = show_footer
	t.cell_defs = [LFTableCellDef.new("id"), LFTableCellDef.new("name")]
	t.set_anchors_preset(Control.PRESET_FULL_RECT)
	host.add_child(t)
	return t


func _cell_text(row: int, column: int) -> String:
	return (table.get_cell(row, column) as Label).text


## Every row the table shows, header and footer included.
func _shown_rows() -> Array:
	var rows := []
	if table.header_section:
		rows.append(table.header_section.get_child(0))
	rows.append_array(table.body.get_children())
	if table.footer_section and table.footer_section.visible:
		rows.append(table.footer_section.get_child(0))
	return rows


func _assert_columns_align(message := "") -> void:
	var rows := _shown_rows()
	var first: LFTableRow = rows[0]
	for row: LFTableRow in rows:
		for column in table.cell_defs.size():
			var cell: Control = row.get_cell(column)
			var reference: Control = first.get_cell(column)
			assert_eq([cell.global_position.x, cell.size.x], [reference.global_position.x, reference.size.x],
				"column %d of row %s %s" % [column, row.name, message])


# --- sections ---------------------------------------------------------------

func test_without_header_or_footer_neither_section_is_built():
	table = _make_table(false, false)

	assert_null(table.header_section)
	assert_null(table.footer_section)
	assert_not_null(table.body)


func test_header_and_footer_are_built_when_declared():
	table = _make_table(true, true)
	table.footer_data = {"id": "Total", "name": 3}

	assert_true(table.header_section is LFTableHeader)
	assert_true(table.footer_section is LFTableFooter)
	assert_eq([table.header_section.get_parent(), table.footer_section.get_parent()], [table, table])
	var header_row: LFTableRow = table.header_section.get_child(0)
	assert_eq([(header_row.get_cell(ID) as Label).text, (header_row.get_cell(NAME) as Label).text], ["id", "name"],
		"the header shows the column titles")
	var footer_row: LFTableRow = table.footer_section.get_child(0)
	assert_true(table.footer_section.visible)
	assert_eq([(footer_row.get_cell(ID) as Label).text, (footer_row.get_cell(NAME) as Label).text], ["Total", "3"],
		"the footer shows footer_data")
	assert_eq(table.row_count(), 0, "neither counts as a body row")


func test_header_body_and_footer_stack_vertically():
	table = _make_table(true, true)
	table.footer_data = {"id": "total"}
	table.add_row({"id": 1, "name": "Alice"})
	await wait_process_frames(2)

	var ys := [table.header_section.position.y, table.body.position.y, table.footer_section.position.y]
	assert_true(ys[0] < ys[1] and ys[1] < ys[2], "sections must stack header, body, footer; got %s" % [ys])


func test_sections_already_in_the_scene_are_adopted_and_put_in_order():
	var t := LFTable.new()
	t.header = true
	t.footer = true
	var body := LFTableBody.new()
	var footer := LFTableFooter.new()
	var header := LFTableHeader.new()
	t.add_child(footer)
	t.add_child(body)
	t.add_child(header)

	host.add_child(t)

	assert_eq([t.header_section, t.body, t.footer_section], [header, body, footer])
	assert_true(header.get_index() < body.get_index() and body.get_index() < footer.get_index())
	assert_eq(t.get_child_count(), 3, "no extra sections are made")


# --- fixed shape and accessors ----------------------------------------------

func test_row_i_is_body_child_i_and_cell_j_is_row_child_j():
	table = _make_table()
	table.set_table_data([{"id": 1, "name": "Alice"}, {"id": 2, "name": "Bob"}])

	assert_eq(table.row_count(), 2)
	assert_eq(table.get_row(1), table.body.get_child(1))
	assert_eq(table.get_cell(1, NAME), table.body.get_child(1).get_child(NAME))
	assert_eq(_cell_text(1, NAME), "Bob")
	assert_eq((table.get_cell(0, ID) as LFTableCell).cell_name, "id")


func test_accessors_out_of_range_return_null():
	table = _make_table()
	table.add_row({"id": 1})

	assert_null(table.get_row(1))
	assert_null(table.get_row(-1))
	assert_null(table.get_cell(0, 2))
	assert_null(table.get_cell(3, 0))


func test_column_index_finds_a_column_by_name():
	table = _make_table()

	assert_eq(table.column_index("name"), NAME)
	assert_eq(table.column_index("missing"), -1)


func test_a_row_missing_a_declared_key_renders_that_cell_empty():
	table = _make_table()
	table.add_row({"id": 2})

	assert_eq(_cell_text(0, NAME), "")


func test_the_header_shows_each_columns_title_or_its_name():
	table = _make_table(true)
	var titled := LFTableCellDef.new("count")
	titled.title = "Count"

	table.cell_defs = [LFTableCellDef.new("id"), titled]

	var header_row: LFTableRow = table.header_section.get_child(0)
	assert_eq(header_row.get_child_count(), 2)
	assert_eq((header_row.get_cell(0) as Label).text, "id")
	assert_eq((header_row.get_cell(1) as Label).text, "Count")


func test_two_columns_on_one_key_keep_their_own_header_titles():
	table = _make_table(true)
	var first := LFTableCellDef.new("id")
	first.title = "Id"
	var second := LFTableCellDef.new("id")
	second.title = "Again"

	table.cell_defs = [first, second]
	second.title = "Twice"
	table.render_header()

	var header_row: LFTableRow = table.header_section.get_child(0)
	assert_eq((header_row.get_cell(0) as Label).text, "Id")
	assert_eq((header_row.get_cell(1) as Label).text, "Twice")


# --- layout ------------------------------------------------------------------

func test_an_auto_column_is_as_wide_as_its_widest_content_on_one_line():
	table = _make_table(true)
	table.set_table_data([{"id": 1, "name": "Fox"}, {"id": 2, "name": "A considerably longer name"}])
	await wait_process_frames(2)

	var long_cell: Label = table.get_cell(1, NAME)
	assert_eq(long_cell.get_line_count(), 1)
	assert_gte(long_cell.size.x, long_cell.get_minimum_size().x)
	assert_gt(long_cell.size.x, 100.0)
	assert_eq(table.get_cell(0, NAME).size.x, long_cell.size.x, "the short cell takes the column's width")


func test_columns_align_across_the_header_and_every_row():
	table = _make_table(true)
	table.set_table_data([
		{"id": 1, "name": "Fox"},
		{"id": 1234567, "name": "A considerably longer name"},
		{"id": 22, "name": ""},
	])
	await wait_process_frames(2)

	_assert_columns_align()


func test_a_fixed_width_column_keeps_its_width_and_clips_longer_text():
	table = _make_table(true)
	table.cell_defs = [LFTableCellDef.new("id", 40.0), LFTableCellDef.new("name")]
	table.set_table_data([{"id": "a very long identifier indeed", "name": "x"}])
	await wait_process_frames(2)

	var id_cell := table.get_cell(0, ID) as Label
	assert_eq(id_cell.size.x, 40.0)
	assert_true(id_cell.clip_text, "the long text is clipped")
	assert_eq(id_cell.text, "a very long identifier indeed", "clipped on screen, not shortened")
	_assert_columns_align()


func test_an_expand_column_takes_the_spare_width_in_every_row():
	table = _make_table(true)
	var name_def := LFTableCellDef.new("name", 0.0, true)
	table.cell_defs = [LFTableCellDef.new("id"), name_def]
	table.set_table_data([{"id": 1, "name": "short"}, {"id": 1000000, "name": "a much longer name than that"}])
	await wait_process_frames(2)

	var name_cell: Control = table.get_cell(0, NAME)
	assert_almost_eq(name_cell.position.x + name_cell.size.x, table.size.x, 1.0)
	_assert_columns_align()


func test_columns_stay_aligned_after_content_changes():
	table = _make_table(true)
	table.set_table_data([{"id": 1, "name": "Fox"}, {"id": 2, "name": "Owl"}])
	await wait_process_frames(2)

	table.set_row(1, {"id": 2, "name": "A much longer owl name"})
	await wait_process_frames(2)

	_assert_columns_align()


func test_a_cell_that_grows_on_its_own_realigns_its_column():
	table = _make_table(true)
	var button_def := LFTableCellDef.new("name")
	button_def.build = func() -> Control: return Button.new()
	table.cell_defs = [LFTableCellDef.new("id"), button_def]
	table.set_table_data([{"id": 1, "name": "Go"}, {"id": 2, "name": "Go"}])
	await wait_process_frames(2)

	(table.get_cell(0, NAME) as Button).text = "A button whose text got much longer"
	await wait_process_frames(3)

	_assert_columns_align()


func test_the_footer_row_aligns_with_the_columns():
	table = _make_table(true, true)
	table.set_table_data([{"id": 1, "name": "Fox"}, {"id": 2, "name": "A considerably longer name"}])
	table.footer_data = {"id": "Total", "name": 2}
	await wait_process_frames(2)

	assert_true(table.footer_section.visible)
	var footer_row: LFTableRow = table.footer_section.get_child(0)
	assert_eq((footer_row.get_cell(ID) as Label).text, "Total")
	_assert_columns_align()


func test_the_footer_is_hidden_without_footer_data():
	table = _make_table(false, true)

	assert_false(table.footer_section.visible)


func test_separations_apply_to_every_row():
	table = _make_table(true)
	table.column_separation = 24
	table.row_separation = 7
	table.add_row({"id": 1})

	assert_eq(table.get_row(0).get_theme_constant("separation"), 24)
	assert_eq(table.header_section.get_child(0).get_theme_constant("separation"), 24)
	assert_eq(table.body.get_theme_constant("separation"), 7)


func test_align_sets_the_text_alignment_of_header_and_cells():
	table = _make_table(true)
	var right := LFTableCellDef.new("name")
	right.align = HORIZONTAL_ALIGNMENT_RIGHT
	table.cell_defs = [LFTableCellDef.new("id"), right]
	table.add_row({"id": 1, "name": "x"})

	assert_eq((table.get_cell(0, NAME) as Label).horizontal_alignment, HORIZONTAL_ALIGNMENT_RIGHT)
	var header_row: LFTableRow = table.header_section.get_child(0)
	assert_eq((header_row.get_cell(NAME) as Label).horizontal_alignment, HORIZONTAL_ALIGNMENT_RIGHT)


# --- cell builders -----------------------------------------------------------

func test_a_column_builder_makes_any_control_a_cell_and_the_updater_fills_it():
	table = _make_table()
	var action := LFTableCellDef.new("name")
	action.build = func() -> Control: return Button.new()
	action.update = func(cell: Control, value: Variant) -> void: (cell as Button).text = "Pick %s" % value
	table.cell_defs = [LFTableCellDef.new("id"), action]

	table.set_table_data([{"id": 1, "name": "Alice"}])

	var button := table.get_cell(0, NAME) as Button
	assert_not_null(button)
	assert_eq(button.text, "Pick Alice")


func test_a_built_cell_without_an_updater_gets_its_text_set():
	table = _make_table()
	var plain := LFTableCellDef.new("name")
	plain.build = func() -> Control: return Button.new()
	table.cell_defs = [LFTableCellDef.new("id"), plain]

	table.add_row({"id": 1, "name": "Alice"})

	assert_eq((table.get_cell(0, NAME) as Button).text, "Alice")


# --- pooling and change detection --------------------------------------------

func test_new_data_of_the_same_size_reuses_the_rows_and_cells():
	table = _make_table()
	table.set_table_data([{"id": 1, "name": "Alice"}, {"id": 2, "name": "Bob"}])
	var row := table.get_row(1)
	var cell := table.get_cell(1, NAME)

	table.set_table_data([{"id": 3, "name": "Carol"}, {"id": 4, "name": "Dan"}])

	assert_eq(table.get_row(1), row)
	assert_eq(table.get_cell(1, NAME), cell)
	assert_eq(_cell_text(1, NAME), "Dan")


func test_the_row_pool_grows_and_shrinks_at_once():
	table = _make_table()
	table.set_table_data([{"id": 1}])
	var first := table.get_row(0)

	table.set_table_data([{"id": 1}, {"id": 2}, {"id": 3}])
	assert_eq(table.body.get_child_count(), 3)
	assert_eq(table.get_row(0), first)

	table.set_table_data([{"id": 9}])
	assert_eq(table.body.get_child_count(), 1, "dropped rows leave the body at once")
	assert_eq(table.get_row(0), first)
	assert_eq(_cell_text(0, ID), "9")


func test_unchanged_data_updates_nothing():
	table = _make_table()
	var calls := [0]
	var counted := LFTableCellDef.new("name")
	counted.update = func(cell: Control, value: Variant) -> void:
		calls[0] += 1
		(cell as Label).text = str(value)
	table.cell_defs = [LFTableCellDef.new("id"), counted]
	table.set_table_data([{"id": 1, "name": "Alice"}, {"id": 2, "name": "Bob"}])
	assert_eq(calls[0], 2)

	table.set_table_data([{"id": 1, "name": "Alice"}, {"id": 2, "name": "Bob"}])

	assert_eq(calls[0], 2, "identical data must not touch any cell")


func test_only_the_cells_whose_value_changed_are_updated():
	table = _make_table()
	var updated := []
	var counted := LFTableCellDef.new("name")
	counted.update = func(cell: Control, value: Variant) -> void:
		updated.append(value)
		(cell as Label).text = str(value)
	table.cell_defs = [LFTableCellDef.new("id"), counted]
	table.set_table_data([{"id": 1, "name": "Alice"}, {"id": 2, "name": "Bob"}])
	updated.clear()

	table.set_table_data([{"id": 1, "name": "Alice"}, {"id": 3, "name": "Bobby"}])

	assert_eq(updated, ["Bobby"])


func _typed_id_table(seen: Array) -> void:
	table = _make_table()
	var typed := LFTableCellDef.new("id")
	typed.update = func(cell: Control, value: Variant) -> void:
		seen.append(typeof(value))
		(cell as Label).text = str(value)
	table.cell_defs = [typed]


func test_a_value_changing_type_but_not_text_is_still_updated():
	var seen := []
	_typed_id_table(seen)
	table.add_row({"id": 1})

	table.set_row(0, {"id": "1"})

	assert_eq(seen, [TYPE_INT, TYPE_STRING], "the cell was refilled with the String")


func test_set_table_data_sees_an_int_turned_float_as_a_change():
	var seen := []
	_typed_id_table(seen)
	table.set_table_data([{"id": 1}])

	table.set_table_data([{"id": 1.0}])

	assert_eq(seen, [TYPE_INT, TYPE_FLOAT], "1 and 1.0 compare equal but show differently")
	assert_eq(_cell_text(0, 0), "1.0")


# --- row operations ----------------------------------------------------------

func test_set_row_replaces_one_row_in_place():
	table = _make_table()
	table.set_table_data([{"id": 1, "name": "Alice"}, {"id": 2, "name": "Bob"}])
	var row := table.get_row(0)

	table.set_row(0, {"id": 1, "name": "Alicia"})

	assert_eq(table.get_row(0), row)
	assert_eq(_cell_text(0, NAME), "Alicia")
	assert_eq(table.rows_data[0]["name"], "Alicia")


func test_remove_row_drops_that_row_and_keeps_the_rest_in_order():
	table = _make_table()
	table.set_table_data([{"id": 1}, {"id": 2}, {"id": 3}])
	var last := table.get_row(2)

	table.remove_row(1)

	assert_eq(table.row_count(), 2)
	assert_eq(table.body.get_child_count(), 2)
	assert_eq(table.get_row(1), last)
	assert_eq(_cell_text(1, ID), "3")
	assert_eq(table.rows_data, [{"id": 1}, {"id": 3}] as Array[Dictionary])


func test_row_operations_out_of_range_warn_and_change_nothing():
	table = _make_table()
	table.add_row({"id": 1})

	table.set_row(5, {"id": 2})
	table.remove_row(-1)

	assert_push_warning_count(2)
	assert_eq(table.row_count(), 1)


func test_add_row_appends_a_row():
	table = _make_table()
	table.add_row({"id": 1})
	table.add_row({"id": 2, "name": "Bob"})

	assert_eq(table.row_count(), 2)
	assert_eq(_cell_text(1, NAME), "Bob")


func test_clear_rows_removes_every_row_at_once():
	table = _make_table()
	table.add_row({"id": 1, "name": "Alice"})

	table.clear_rows()

	assert_eq(table.body.get_child_count(), 0)
	assert_eq(table.rows_data.size(), 0)


func test_set_table_data_with_its_own_rows_data_keeps_every_row():
	table = _make_table()
	table.set_table_data([{"id": 1}, {"id": 2}])

	table.set_table_data(table.rows_data)

	assert_eq(table.body.get_child_count(), 2)
	assert_eq(table.rows_data.size(), 2)


func test_editing_the_rows_data_read_back_and_passing_it_again_shows_the_edit():
	table = _make_table()
	table.set_table_data([{"id": 1, "name": "Alice"}])

	var rows := table.rows_data
	rows[0]["name"] = "Alicia"
	assert_eq(_cell_text(0, NAME), "Alice", "nothing changes until the rows are passed")
	table.set_table_data(rows)

	assert_eq(_cell_text(0, NAME), "Alicia")


func test_rows_that_are_not_dictionaries_are_skipped_with_a_warning():
	table = _make_table()

	table.set_table_data([{"id": 1}, "oops", {"id": 2}])

	assert_push_warning("oops")
	assert_eq(table.row_count(), 2)
	assert_eq(_cell_text(1, ID), "2")


func test_rows_data_keeps_its_own_copy_of_each_row():
	table = _make_table()
	var row := {"id": 1, "name": "Alice"}
	table.set_table_data([row])

	row["name"] = "Changed"
	assert_eq(table.rows_data[0]["name"], "Alice", "the caller's dictionary is not shared")

	table.set_table_data([row])
	assert_eq(_cell_text(0, NAME), "Changed")


func test_new_columns_rebuild_existing_rows_and_the_header():
	table = _make_table(true)
	table.set_table_data([{"id": 1, "name": "Alice", "value": 5}])

	table.cell_defs = [LFTableCellDef.new("value")]

	assert_eq(table.get_row(0).get_child_count(), 1)
	assert_eq(_cell_text(0, 0), "5")
	var header_row: LFTableRow = table.header_section.get_child(0)
	assert_eq(header_row.get_child_count(), 1)
	assert_eq((header_row.get_cell(0) as Label).text, "value")


# --- before ready ------------------------------------------------------------

func test_rows_added_before_ready_are_shown_once_ready():
	var t := LFTable.new()
	t.header = false
	t.cell_defs = [LFTableCellDef.new("id")]
	t.add_row({"id": 1})
	t.set_table_data([{"id": 2}, {"id": 3}])
	t.add_row({"id": 4})
	assert_null(t.get_row(0), "no rows exist before ready")

	host.add_child(t)
	table = t

	assert_eq(table.row_count(), 3)
	assert_eq(_cell_text(2, 0), "4")


func test_ready_shows_a_preset_rows_data_export():
	var t := LFTable.new()
	t.header = false
	t.cell_defs = [LFTableCellDef.new("id")]
	t.rows_data = [{"id": 1}, {"id": 2}]

	host.add_child(t)

	assert_eq(t.body.get_child_count(), 2)


# --- column definition -------------------------------------------------------

func test_a_column_definition_defaults_to_an_auto_width_left_aligned_text_column():
	var def := LFTableCellDef.new("id")

	assert_eq([def.cell_name, def.title, def.min_width, def.min_height, def.expand, def.align],
		["id", "", 0.0, 0.0, false, HORIZONTAL_ALIGNMENT_LEFT])
	assert_eq(def.get_title(), "id")
	assert_true(autofree(def.make_cell()) is LFTableCell)


func test_min_height_applies_to_every_cell_of_the_column():
	table = _make_table()
	var tall := LFTableCellDef.new("name")
	tall.min_height = 30.0
	table.cell_defs = [LFTableCellDef.new("id"), tall]
	table.add_row({"id": 1, "name": "x"})
	await wait_process_frames(1) # columns are measured at the end of the frame

	assert_eq(table.get_cell(0, NAME).custom_minimum_size.y, 30.0)


func test_an_empty_title_can_stay_blank_instead_of_showing_the_key():
	var plain := LFTableCellDef.new('kind')
	assert_eq(plain.get_title(), 'kind', 'by default an empty title shows the key')
	plain.title_from_key = false
	assert_eq(plain.get_title(), '')
	plain.title = 'Kind'
	assert_eq(plain.get_title(), 'Kind', 'a title given is always shown')


func test_default_text_cells_clip_only_with_a_min_width_or_expand():
	assert_true(autofree(LFTableCellDef.new("a", 40.0).make_text_cell()).clip_text, "fixed width")
	assert_true(autofree(LFTableCellDef.new("a", 0.0, true).make_text_cell()).clip_text, "expand")
	assert_false(autofree(LFTableCellDef.new("a").make_text_cell()).clip_text, "sized to its content")


func test_a_separation_of_minus_one_restores_the_theme_value():
	table = _make_table(true)
	table.add_row({"id": 1})
	var theme_column := table.get_row(0).get_theme_constant("separation")
	var theme_row := table.body.get_theme_constant("separation")
	table.column_separation = 24
	table.row_separation = 7

	table.column_separation = -1
	table.row_separation = -1

	assert_false(table.get_row(0).has_theme_constant_override("separation"))
	assert_eq(table.get_row(0).get_theme_constant("separation"), theme_column)
	assert_eq(table.header_section.get_child(0).get_theme_constant("separation"), theme_column)
	assert_eq(table.body.get_theme_constant("separation"), theme_row)


func test_emptying_the_footer_data_hides_the_footer_again():
	table = _make_table(false, true)
	table.footer_data = {"id": "Total"}
	assert_true(table.footer_section.visible)

	table.footer_data = {}

	assert_false(table.footer_section.visible)


# --- strips -------------------------------------------------------------------

var _updates: Array = []


func _card_template() -> LFTableCellDef:
	var template := LFTableCellDef.new("card", 120.0)
	template.min_height = 40.0
	template.build = func() -> Control: return Button.new()
	template.update = func(cell: Control, value: Variant) -> void:
		_updates.append(value)
		(cell as Button).text = str(value)
	return template


func _strip_texts() -> Array:
	var texts := []
	for i in table.strip_size():
		texts.append((table.strip_cell(i) as Button).text)
	return texts


func test_a_strip_lays_items_out_as_one_row_of_template_cells():
	table = _make_table()
	_updates = []

	table.set_strip(["a", "b", "c"], _card_template())

	assert_eq(table.row_count(), 1)
	assert_eq(table.strip_size(), 3)
	assert_eq(_strip_texts(), ["a", "b", "c"])
	assert_eq(table.cell_defs.map(func(d): return d.cell_name), ["0", "1", "2"])
	assert_eq(table.cell_defs[2].min_width, 120.0)
	assert_eq(table.cell_defs[2].min_height, 40.0)
	assert_null(table.strip_cell(3))
	assert_null(table.strip_cell(-1))


func test_a_strip_of_the_same_count_refills_its_cells_in_place():
	table = _make_table()
	var template := _card_template()
	table.set_strip(["a", "b"], template)
	var first := table.strip_cell(0)
	var second := table.strip_cell(1)

	table.set_strip(["a", "z"], template)

	assert_eq(table.strip_cell(0), first, "kept, not rebuilt")
	assert_eq(table.strip_cell(1), second)
	assert_eq(_strip_texts(), ["a", "z"])


func test_an_unchanged_strip_item_does_nothing():
	table = _make_table()
	var template := _card_template()
	table.set_strip(["a", "b"], template)
	_updates = []

	table.set_strip(["a", "c"], template)
	table.set_strip(["a", "c"], template)

	assert_eq(_updates, ["c"], "only the changed card was refilled, once")


func test_a_count_change_rebuilds_the_strips_columns():
	table = _make_table()
	var template := _card_template()
	table.set_strip(["a", "b"], template)
	var first := table.strip_cell(0)

	table.set_strip(["a", "b", "c"], template)

	assert_eq(table.strip_size(), 3)
	assert_ne(table.strip_cell(0), first, "new columns, new cells")
	assert_eq(_strip_texts(), ["a", "b", "c"])
	assert_eq(table.get_row(0).get_child_count(), 3)


func test_an_empty_strip_has_no_row():
	table = _make_table()
	table.set_strip(["a"], _card_template())

	table.set_strip([], _card_template())

	assert_eq(table.row_count(), 0)
	assert_eq(table.strip_size(), 0)
	assert_null(table.strip_cell(0))


func test_a_strip_set_before_ready_shows_once_ready():
	_updates = []
	table = LFTable.new()
	table.header = false
	table.set_strip(["x", "y"], _card_template())
	host.add_child(table)

	assert_eq(_strip_texts(), ["x", "y"])


func test_a_strip_after_columns_set_by_hand_rebuilds_its_columns():
	table = _make_table()
	var template := _card_template()
	table.set_strip(["a", "b"], template)

	table.cell_defs = [LFTableCellDef.new("id"), LFTableCellDef.new("name")]
	assert_eq(table.strip_size(), 0, "hand-set columns are not a strip")

	table.set_strip(["a", "b"], template)
	assert_eq(table.strip_size(), 2)
	assert_eq(_strip_texts(), ["a", "b"])


func test_a_strip_without_a_template_is_refused():
	table = _make_table()
	table.add_row({"id": 1})

	table.set_strip(["a"], null)

	assert_push_error("template")
	assert_eq(table.strip_size(), 0)
	assert_eq(table.row_count(), 1, "nothing changed")


func test_render_header_refills_titles_changed_in_place():
	table = _make_table(true)
	table.cell_defs[NAME].title = "Name"

	table.render_header()

	var header_row: LFTableRow = table.header_section.get_child(0)
	assert_eq((header_row.get_cell(NAME) as Label).text, "Name")


func test_a_row_keeps_a_copy_of_the_data_it_shows():
	table = _make_table()
	var data := {"id": 1, "name": "Alice"}
	table.add_row(data)
	data["name"] = "Changed"

	assert_eq(table.get_row(0).row_data, {"id": 1, "name": "Alice"}, "a copy, not the caller's dictionary")
	assert_null(table.get_row(0).get_cell(-1))
	assert_null(table.get_row(0).get_cell(2))


func test_fill_cell_writes_text_without_an_updater():
	var def := LFTableCellDef.new("id")
	var label: LFTableCell = autofree(def.make_text_cell())
	var button: Button = autofree(Button.new())
	def.fill_cell(label, 5)
	def.fill_cell(button, null)

	assert_eq([label.text, button.text], ["5", ""])
	assert_eq(label.cell_name, "id")


func test_a_text_cell_shows_its_content_as_text_and_null_as_nothing():
	var cell: LFTableCell = autofree(LFTableCell.new())

	cell.set_cell_content(12.5)
	assert_eq(cell.text, "12.5")
	cell.set_cell_content(null)
	assert_eq(cell.text, "")


func test_a_row_signals_when_a_cell_changes_its_minimum_size_on_its_own():
	var row: LFTableRow = add_child_autofree(LFTableRow.new())
	var def := LFTableCellDef.new("name")
	def.build = func() -> Control: return Button.new()
	var defs: Array[LFTableCellDef] = [def]
	row.set_row_data({"name": "Go"}, defs)
	watch_signals(row)

	(row.get_cell(0) as Button).text = "A much longer button text"
	await wait_process_frames(2)

	assert_signal_emitted(row, "cell_minimum_size_changed")


func test_make_cell_uses_the_columns_builder():
	var def := LFTableCellDef.new("pick")
	def.build = func() -> Control: return Button.new()

	assert_true(autofree(def.make_cell()) is Button)


# --- remaining paths ----------------------------------------------------------

func test_set_row_and_remove_row_before_ready_are_shown_once_ready():
	var t := LFTable.new()
	t.header = false
	t.cell_defs = [LFTableCellDef.new("id")]
	t.set_table_data([{"id": 1}, {"id": 2}, {"id": 3}])
	t.set_row(0, {"id": 10})
	t.remove_row(1)
	assert_eq(t.rows_data, [{"id": 10}, {"id": 3}] as Array[Dictionary])

	host.add_child(t)
	table = t

	assert_eq(table.body.get_child_count(), 2)
	assert_eq([_cell_text(0, 0), _cell_text(1, 0)], ["10", "3"])


func test_a_theme_change_realigns_the_columns_to_the_new_text_size():
	table = _make_table(true)
	table.set_table_data([{"id": 1, "name": "Alice"}, {"id": 22, "name": "Bob"}])
	await wait_process_frames(2)
	var narrow := table.get_cell(0, NAME).custom_minimum_size.x

	var big := Theme.new()
	big.default_font_size = 40
	table.theme = big
	await wait_process_frames(2)

	assert_gt(table.get_cell(0, NAME).custom_minimum_size.x, narrow, "the column grew with the font")
	_assert_columns_align("after the theme change")


func test_footer_data_set_before_ready_is_shown_once_ready_and_is_copied():
	var totals := {"id": "Total", "name": 3}
	var t := LFTable.new()
	t.header = false
	t.footer = true
	t.cell_defs = [LFTableCellDef.new("id"), LFTableCellDef.new("name")]
	t.footer_data = totals
	totals["name"] = 99

	host.add_child(t)
	table = t

	assert_true(table.footer_section.visible)
	var footer_row: LFTableRow = table.footer_section.get_child(0)
	assert_eq((footer_row.get_cell(NAME) as Label).text, "3", "the caller's dictionary is not shared")
	assert_eq(table.footer_data["name"], 3)


func test_header_and_footer_cells_stay_text_even_for_a_built_column():
	table = _make_table(true, true)
	var button_column := LFTableCellDef.new("name")
	button_column.build = func() -> Control: return Button.new()
	table.cell_defs = [LFTableCellDef.new("id"), button_column]
	table.footer_data = {"name": "Sum"}
	table.add_row({"id": 1, "name": "Go"})

	assert_true(table.get_cell(0, NAME) is Button)
	assert_true(table.header_section.get_child(0).get_cell(NAME) is LFTableCell)
	assert_true(table.footer_section.get_child(0).get_cell(NAME) is LFTableCell)
	assert_eq((table.footer_section.get_child(0).get_cell(NAME) as Label).text, "Sum")


func test_separations_set_before_ready_apply_and_reach_rows_added_later():
	var t := LFTable.new()
	t.cell_defs = [LFTableCellDef.new("id")]
	t.column_separation = 18
	t.row_separation = 5
	host.add_child(t)
	table = t

	table.add_row({"id": 1})
	table.set_table_data([{"id": 1}, {"id": 2}])

	assert_eq(table.get_row(1).get_theme_constant("separation"), 18)
	assert_eq(table.header_section.get_child(0).get_theme_constant("separation"), 18)
	assert_eq(table.body.get_theme_constant("separation"), 5)


func test_skipped_rows_around_unchanged_data_change_nothing():
	table = _make_table()
	var calls := [0]
	var counted := LFTableCellDef.new("id")
	counted.update = func(cell: Control, value: Variant) -> void:
		calls[0] += 1
		(cell as Label).text = str(value)
	table.cell_defs = [counted]
	table.set_table_data([{"id": 1}])
	calls[0] = 0

	table.set_table_data([{"id": 1}, 42])

	assert_push_warning("42")
	assert_eq(calls[0], 0, "the remaining rows equal the shown ones")
	assert_eq(table.row_count(), 1)


func test_a_key_turning_from_null_to_missing_refills_its_cell():
	table = _make_table()
	var seen := []
	var counted := LFTableCellDef.new("name")
	counted.update = func(cell: Control, value: Variant) -> void:
		seen.append(value)
		(cell as Label).text = "" if value == null else str(value)
	table.cell_defs = [counted]
	table.set_table_data([{"name": null}])
	seen.clear()

	table.set_table_data([{}])

	assert_eq(seen, [null], "a key that appears or disappears counts as a change")


func test_a_strip_column_copies_every_setting_of_its_template():
	table = _make_table()
	var template := LFTableCellDef.new("ignored", 50.0, true)
	template.title = "Card"
	template.title_from_key = false
	template.min_height = 12.0
	template.align = HORIZONTAL_ALIGNMENT_CENTER

	table.set_strip(["a", "b"], template)

	var column: LFTableCellDef = table.cell_defs[1]
	assert_eq([column.cell_name, column.title, column.title_from_key, column.min_width, column.min_height, column.expand, column.align],
		["1", "Card", false, 50.0, 12.0, true, HORIZONTAL_ALIGNMENT_CENTER])
	assert_ne(column, template, "a copy, not the template itself")
	assert_eq((table.strip_cell(1) as Label).text, "b")


func test_an_empty_strip_on_an_empty_table_does_nothing():
	table = _make_table()
	table.cell_defs = []

	table.set_strip([], LFTableCellDef.new())

	assert_eq(table.row_count(), 0)
	assert_eq(table.strip_size(), 0)


func test_a_new_template_object_rebuilds_a_strip_of_the_same_count():
	table = _make_table()
	table.set_strip(["a", "b"], _card_template())
	var first := table.strip_cell(0)

	table.set_strip(["a", "b"], _card_template())

	assert_ne(table.strip_cell(0), first, "another template means new columns")
	assert_eq(_strip_texts(), ["a", "b"])


func test_fill_cell_leaves_a_cell_without_text_alone():
	var def := LFTableCellDef.new("colour")
	var swatch: ColorRect = autofree(ColorRect.new())

	def.fill_cell(swatch, Color.RED)

	assert_eq(swatch.color, Color.WHITE, "no text property, nothing written")


func test_a_titled_column_shows_its_title_even_with_title_from_key_off():
	var def := LFTableCellDef.new("hp")
	def.title = "Health"
	def.title_from_key = false

	assert_eq(def.get_title(), "Health")


func test_cells_expand_only_in_an_expand_column():
	table = _make_table()
	table.cell_defs = [LFTableCellDef.new("id"), LFTableCellDef.new("name", 0.0, true)]
	table.add_row({"id": 1, "name": "x"})

	assert_eq(table.get_cell(0, ID).size_flags_horizontal, Control.SIZE_FILL)
	assert_eq(table.get_cell(0, NAME).size_flags_horizontal, Control.SIZE_EXPAND_FILL)


func test_strip_cells_and_rows_are_null_before_ready():
	var t: LFTable = autofree(LFTable.new())
	t.header = false

	t.set_strip(["x", "y"], _card_template())

	assert_eq(t.strip_size(), 2)
	assert_null(t.strip_cell(0))
	assert_null(t.get_cell(0, 0))


func test_set_row_with_the_data_already_shown_touches_no_node():
	table = _make_table(true)
	table.set_table_data([{"id": 1, "name": "Alice"}, {"id": 2, "name": "Bob"}, {"id": 3, "name": "Carol"}])
	var cell := table.get_cell(2, NAME)
	cell.custom_minimum_size = Vector2(321, 0) # what a column re-measure would overwrite

	table.set_row(1, {"id": 2, "name": "Bob"})

	assert_eq(cell.custom_minimum_size, Vector2(321, 0), "the columns were not measured again")
	assert_eq(_cell_text(1, NAME), "Bob")


func test_setting_the_same_defs_again_shows_a_title_changed_in_place_but_not_an_alignment():
	table = _make_table(true)
	table.add_row({"id": 1, "name": "x"})
	var defs := table.cell_defs
	defs[NAME].title = "Name"
	defs[NAME].align = HORIZONTAL_ALIGNMENT_RIGHT

	table.cell_defs = defs

	var header_row: LFTableRow = table.header_section.get_child(0)
	assert_eq((header_row.get_cell(NAME) as Label).text, "Name")
	assert_eq((table.get_cell(0, NAME) as Label).horizontal_alignment, HORIZONTAL_ALIGNMENT_LEFT, "the old cell is kept")


func test_new_def_objects_apply_an_alignment_to_existing_rows():
	table = _make_table(true)
	table.add_row({"id": 1, "name": "x"})
	var right := LFTableCellDef.new("name")
	right.align = HORIZONTAL_ALIGNMENT_RIGHT

	table.cell_defs = [table.cell_defs[ID], right]

	assert_eq((table.get_cell(0, NAME) as Label).horizontal_alignment, HORIZONTAL_ALIGNMENT_RIGHT)
	assert_eq(_cell_text(0, NAME), "x")


## A burst of row changes in one frame measures the columns once, at the end of the frame,
## and the widths then fit the last data.
func test_row_changes_measure_the_columns_once_at_the_end_of_the_frame():
	table = _make_table(true)
	var rows: Array = []
	for i in 50:
		rows.append({"id": i, "name": "Unit %d" % i})
	table.set_table_data(rows)
	await wait_process_frames(1)
	var cell := table.get_cell(7, NAME)
	cell.custom_minimum_size = Vector2(321, 0) # what a column re-measure would overwrite

	for k in 20:
		table.set_row(7, {"id": 7, "name": "Unit 7 renamed %d" % k})
	table.add_row({"id": 50, "name": "Late"})
	table.set_table_data(table.rows_data)

	assert_eq(cell.custom_minimum_size, Vector2(321, 0), "not measured during the burst")
	await wait_process_frames(1)
	var widest := 0.0
	for row in table.row_count():
		widest = maxf(widest, table.get_cell(row, NAME).get_minimum_size().x)
	assert_eq(cell.custom_minimum_size.x, widest, "measured once the frame ends, to the widest cell")
	assert_eq(_cell_text(7, NAME), "Unit 7 renamed 19")


## Editing the dictionary a row hands back changes neither the row nor what the table
## compares new data with.
func test_editing_a_rows_data_read_back_changes_nothing():
	table = _make_table()
	table.add_row({"id": 1, "name": "Alice"})
	var read := table.get_row(0).row_data
	read["name"] = "Mallory"

	table.set_row(0, {"id": 1, "name": "Mallory"})

	assert_eq(_cell_text(0, NAME), "Mallory", "the change was seen and shown")
	assert_eq(table.get_row(0).row_data, {"id": 1, "name": "Mallory"})
