# LFBarChart

> A small bar chart for your UI: one bar per value, scaled to the largest, with value labels above; setting `values` redraws.

| | |
|---|---|
| **Kind** | [Node](../../../README.md#how-lf-classes-work): add it to a scene |
| **Files** | `lf_bar_chart.gd` |
| **Tests** | `tests/test_lf_bar_chart.gd` (in the repository; the release zip leaves tests out) |
| **Depends on** | — |

## When to use it

Use it for a quick at-a-glance history inside a menu or HUD: points scored in each of the
last ten rounds, or enemies killed per wave on a results screen. Add it like any Control,
give it a size, and assign `values`; it scales and redraws itself. It has no axes, ticks,
legend or hover, so for a full chart with those, draw your own in `_draw()` or use a
charting add-on. For a single value that fills up (health, progress), use Godot's
`ProgressBar` or `TextureProgressBar`.

## Step by step

1. In Godot choose *Scene → New Scene*. In the Scene dock click **User Interface** (it
   creates a `Control` root that fills the window). Save with Ctrl+S, for example as
   `chart_demo.tscn`.
2. Click **+ Add Child Node** at the top of the Scene dock, type `LFBarChart`, select it and
   press *Create*. The chart appears as a child of the root.
3. Select it. In the Inspector open *Layout → Custom Minimum Size* and set x = `320`,
   y = `160` (pixels). Without a size the chart is 0 px big and you will see nothing.
4. Optional looks, also in the Inspector: *Bar Color*, *Label Color*, *Axis Color*,
   *Font Size*, *Bar Ratio* (how wide each bar is inside its slot, 0.05 to 1), *Show Values*.
5. Select the root node, click the **Attach Script** icon (a scroll with a +) at the top of
   the Scene dock, press *Create*, and replace the script's contents with:

   ```gdscript
   extends Control

   # "$LFBarChart" is the child node named LFBarChart. Use the name shown in your
   # Scene dock if it differs.
   @onready var chart: LFBarChart = $LFBarChart


   func _ready() -> void:   # runs once when the scene starts
   	chart.values = [3, 7, 2, 9]   # one bar per number, left to right; setting it redraws
   ```
6. Press **F6** (*Run Current Scene*). You should see four bars, the tallest (9) reaching
   near the top, each with its number above it and a thin baseline underneath. To change
   the chart later, assign a new list: `chart.values = [5, 1, 8]`.

## API

Everything the class offers; you only need the rows used above to get started. A Callable is a function passed around as a value, such as `func(v): return "%d pts" % v`.

| Member | Signature | Description |
|---|---|---|
| `DEFAULT_BAR_COLOR`, `DEFAULT_LABEL_COLOR`, `DEFAULT_AXIS_COLOR` | `const Color` | Defaults of the three colours. |
| `DEFAULT_FONT_SIZE` | `const int` (11) | Default `font_size`. |
| `DEFAULT_BAR_RATIO` | `const float` (0.6) | Default `bar_ratio`. |
| `DEFAULT_TOP_PADDING`, `DEFAULT_BOTTOM_PADDING` | `const float` (24.0, 4.0) | Defaults of the two paddings. |
| `values` | `var values: Array` | Numbers left to right (copied on set). Setting it redraws. Negative values, NaN, infinities and non-numbers draw as 0. |
| `bar_color`, `label_color`, `axis_color` | `@export var … := DEFAULT_BAR_COLOR` (`#5a8dee`), `DEFAULT_LABEL_COLOR` (`Color(0.9, 0.9, 0.9)`), `DEFAULT_AXIS_COLOR` (`Color(0.5, 0.5, 0.5)`) | Bar fill, value label and baseline colours. |
| `font_size` | `@export var font_size := DEFAULT_FONT_SIZE` (11) | Value label size, in pixels. |
| `bar_ratio` | `@export_range(0.05, 1.0) var bar_ratio := DEFAULT_BAR_RATIO` (0.6) | Share of each slot the bar fills (the rest is the gap). |
| `show_values` | `@export var show_values := true` | Print each value above its bar. |
| `top_padding`, `bottom_padding` | `@export var … := DEFAULT_TOP_PADDING` (24.0), `DEFAULT_BOTTOM_PADDING` (4.0) | Room above the tallest bar (for its label) and below the baseline. |
| `value_text` | `var value_text: Callable` | `func(value) -> String` for the labels; unset rounds each value to two decimals and drops trailing zeros (`3`, `2.5`, `3.14`; `2.999` prints `3`). Setting it does not redraw. |
| `bar_rects` | `bar_rects() -> Array[Rect2]` | Each bar's local rectangle, in `values` order: what is drawn. |
| `format_value` | `format_value(value: Variant) -> String` | The label printed for `value`. |
| `value_label_rects` | `value_label_rects() -> Array[Rect2]` | Where each value label is drawn (local coordinates): its text's rect, centred on its bar, 4 px above the bar's top. Empty without values or a font. |

## Usage

```gdscript
# results_screen.gd, on a VBoxContainer in the results screen.
extends VBoxContainer

var chart := LFBarChart.new()


func _ready() -> void:
	chart.custom_minimum_size = Vector2(0, 120)    # inside a container, give it a height
	chart.bar_color = Color.GOLD
	chart.value_text = func(value): return "%d pts" % value
	add_child(chart)
	chart.values = [120, 340, 90, 410]             # redraws on its own


# Call this after each round; assigning a new array redraws the chart.
func show_history(points_per_round: Array) -> void:
	chart.values = points_per_round
```

## Notes

- The largest value reaches `top_padding` below the top edge; when every value is 0 or less the bars stay flat (the scale never divides by zero). A NaN ("not a number", what `0.0 / 0.0` gives) or infinite value draws as 0 and does not change the scale.
- Every style property redraws on set; there is no need to call `queue_redraw()` (Godot's "repaint this control" call). `value_text` is the exception: set it before `values`, or call `queue_redraw()` after.
- `values` is copied when set, and editing it in place (`chart.values.append(5)`) does not redraw; assign a new array instead.
- Labels use the theme's default font. Without a font (some headless setups) only the labels are skipped.
- There are no axes, ticks or hover; it is meant for small at-a-glance histories.
