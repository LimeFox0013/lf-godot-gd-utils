## The default LFTable cell: a Label without word wrap showing its value as text, tagged
## with the column it belongs to. A line break in the value still starts a new line.
class_name LFTableCell
extends Label

## Column (LFTableCellDef.cell_name) this cell belongs to.
@export var cell_name: String


## Shows `str(content)`, or nothing for null.
func set_cell_content(content: Variant) -> void:
	text = "" if content == null else str(content)
