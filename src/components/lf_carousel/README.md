# LFCarousel, LFCarouselPage

> A screen that shows one page at a time and slides smoothly to another page when you ask.

| | |
|---|---|
| **Files** | `lf_carousel.gd`, `lf_carousel_page.gd` |
| **Tests** | `tests/test_lf_carousel.gd` (in the repository; the release zip leaves tests out) |
| **Depends on** | `LFAwait` (`all`, used by the default transition), `LFLogger` |

**Classes** ([how LF classes work](../../../README.md#how-lf-classes-work)):

| Class | How you use it |
|---|---|
| `LFCarousel` | Node: add it to a scene |
| `LFCarouselPage` | Node: add it to a scene |

## When to use it

Use it to switch between full screens or panels with an animation: a main menu that
slides from "Play" to "Options" to "Credits", the steps of a character-creation wizard,
or tabbed pages of a codex. Each page is just a child Control, switched by its node name,
and `await carousel.activate_slide("Options")` waits until the animation is over. The
animation is a function you can swap (`slide_fn`) for a fade or an instant cut. If you
need no animation at all, Godot's `TabContainer` (with `tabs_visible = false`) is
simpler.

## Step by step

1. *Scene → New Scene*, then click **User Interface** (a `Control` root). Rename it `MainMenu` and save (*Ctrl+S*, or *Cmd+S* on macOS) as `carousel_demo.tscn`. Make it fill the window: in the Inspector open *Layout → Anchors Preset* and pick **Full Rect** (the toolbar above the viewport has the same *Layout* menu).
2. Click **+ Add Child Node**, search `LFCarousel`, and create it. Give it **Full Rect** too.
3. Select the `LFCarousel` node and add three **ColorRect** children. Rename them exactly `Play`, `Options` and `Credits`; their names are how you ask for them. Give each one **Full Rect** the same way and a different *Color* in the Inspector. Add a **Label** to each with some text. The first page in the tree (`Play`) is the one shown at start.
4. Select `MainMenu`, right-click it, choose **Attach Script**, click *Create*, and use this code. It adds a row of buttons, one per page. `await` means "wait here until the animation has finished".

```gdscript
extends Control

@onready var carousel: LFCarousel = $LFCarousel


func _ready() -> void:
	# A row of buttons, one per page, drawn above the pages (z_index 10).
	var bar := HBoxContainer.new()
	bar.z_index = 10
	add_child(bar)
	for page_name in carousel.slides_order:
		LFBuild.button(bar, page_name, func() -> void: carousel.activate_slide(page_name))
	carousel.slide_changed.connect(func(shown: String) -> void: print("now on ", shown))
```

5. Press **F6** (*Run Current Scene*). You should see the `Play` page and three buttons in the top-left corner. Click **Options**: the old page slides out to the left while the new one comes in from the right (about a quarter of a second), and the Output panel prints "now on Options". Click **Play** to slide back the other way.

To wait for the animation in your own code, use `await carousel.activate_slide("Credits")`; the next line runs once the slide is over.

## API

Everything the class offers; you only need the rows used above to get started.

### Signals

| Member | Signature | Description |
|---|---|---|
| `slide_switch_started` | `signal slide_switch_started(from: String, to: String)` | Emitted when a switch starts, before the transition runs. |
| `slide_changed` | `signal slide_changed(slide_name: String)` | Emitted after the transition finishes and `current_slide` is updated. Not emitted for a switch `setup()` cancelled, or one whose target page was freed meanwhile while the old page survived (if both were freed, it is emitted for the first surviving page). |

### Exports / Properties

| Member | Signature | Description |
|---|---|---|
| `auto_setup` | `@export var auto_setup := true` | Call `setup()` in `_ready()`. |
| `DEFAULT_TWEEN_DURATION` | `const DEFAULT_TWEEN_DURATION := 0.25` | Default `move_slide` duration (seconds). |
| `slide_fn` | `var slide_fn: Callable = LFCarousel.x_shift_out` | Transition strategy `func(carousel: LFCarousel, next_slide_name: String)`; awaited. When it returns, the carousel hides every page but the new current one. |
| `current_slide` | `var current_slide: String` | Name of the active page (`""` when there are no pages). |
| `slides_map` | `var slides_map: Dictionary[String, Control]` | Pages by node name, as of the last `setup()`. |
| `slides_order` | `var slides_order: Array[String]` | Page names in child order, as of the last `setup()`. |
| `is_switching` | `var is_switching := false` | True while `activate_slide` runs a transition. Read it; don't set it. |

### Methods

| Member | Signature | Description |
|---|---|---|
| `setup` | `setup(init_slide_name := current_slide) -> void` | Ends a running switch (its tweens jump to their end, its result is dropped), rebuilds the map from every `Control` child, puts each page's `position` back at `(0, 0)`, shows `init_slide_name` and hides the rest. An empty name picks the first page; an unknown name pushes a warning and picks the first page. |
| `get_slide_index` | `get_slide_index(slide_name: String) -> int` | Index in `slides_order`, `-1` if absent. |
| `set_slide_state` | `set_slide_state(slide_name: String, state: bool) -> void` | Sets `visible = state` and `z_index` 1/0. An unknown or freed page warns and is ignored. |
| `activate_slide` | `activate_slide(slide_name: String) -> void` | Coroutine (`await` it to wait for the animation; calling it without `await` also works). No-op if already current or while another switch runs; an unknown name warns and is ignored. Otherwise raises the next page's `z_index`, emits `slide_switch_started`, awaits `slide_fn`, sets `current_slide`, leaves exactly that page visible and emits `slide_changed`. If the target page was freed meanwhile, the old page stays current; if both were freed, the first surviving page becomes current. |
| `instant` | `static instant(carousel: LFCarousel, next_slide_name: String) -> void` | A `slide_fn` with no animation: the next page shows and the carousel hides the rest. |
| `x_shift_out` | `static x_shift_out(carousel: LFCarousel, next_slide_name: String) -> void` | Default strategy: concurrently slides the current page out (0.28 s) and the next in from the opposite side (0.21 s) — a later page comes in from the right, an earlier one from the left — then hides the old page. |
| `move_slide` | `move_slide(slide_name: String, to: Vector2, from: Variant = null, duration := DEFAULT_TWEEN_DURATION, tween_trans := Tween.TRANS_LINEAR, tween_ease := Tween.EASE_IN) -> void` | Coroutine: shows the page, jumps to `from` when it is a `Vector2` (`null` keeps the current position; `Vector2.ZERO` is a real jump), tweens `position` to `to` along the `tween_trans` curve with `tween_ease`. `duration` is in seconds; `duration <= 0` sets it at once. Parameter order as `LFAnimate.control` (duration, curve, easing). The tween belongs to the carousel, so it finishes even if the page is freed. An unknown or freed page warns and returns. |

## Usage

Scene: an `LFCarousel` node (full rect) with three Control children named `Play`,
`Options` and `Credits`, plus a menu script on its parent:

```gdscript
# main_menu.gd: attach to the parent of the LFCarousel node.
extends Control

@onready var carousel: LFCarousel = $LFCarousel


func _ready() -> void:
	# The carousel already showed its first page ("Play") in its own _ready().
	carousel.slide_changed.connect(func(page: String) -> void: print("now on ", page))


func _on_options_pressed() -> void:  # connect your Options button here
	await carousel.activate_slide("Options")  # slides Play out, Options in
	print("animation done, current page: ", carousel.current_slide)


func use_instant_switch() -> void:
	# Replace the animation: show the next page at once. Once the function returns,
	# the carousel hides every other page.
	carousel.slide_fn = LFCarousel.instant


func reload_pages() -> void:
	# After adding, removing or renaming pages, rebuild the page list.
	carousel.setup("Play")
```

## Notes

- Every `Control` child is a page; other nodes are ignored. `LFCarouselPage` is only a convenience base.
- Pages are keyed by node name as of the last `setup()`. Call `setup()` again after adding, removing or renaming a page; a renamed page is unreachable by its new name until then. A freed page is skipped.
- A request made while a transition is running is dropped, not queued. A custom `slide_fn` that never returns leaves `is_switching` set until `setup()` runs; `setup()` always clears it.
- `setup()` during a switch fast-forwards the default strategy's tweens; a custom `slide_fn` awaiting something else keeps running, but its switch no longer changes `current_slide` or emits `slide_changed`.
- Tweens run only while the carousel is inside the tree: a carousel removed mid-switch stays busy and finishes the switch once it is back. Outside the tree, `move_slide` (so the default transition) moves pages at once and `activate_slide` completes immediately.
- An invalid `slide_fn` makes `activate_slide` push an error and do nothing.
- `tween_ease` shapes the motion only along a curve: with the default `Tween.TRANS_LINEAR` every ease moves at a constant speed. Pass a curve such as `Tween.TRANS_QUAD` or `Tween.TRANS_BACK` for a slide that speeds up, slows down or overshoots.
- `slide_fn` is a plain property (a Callable, a function stored in a variable, cannot be set in the Inspector); assign it from code.
