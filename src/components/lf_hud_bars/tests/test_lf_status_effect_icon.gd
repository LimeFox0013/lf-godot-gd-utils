extends GutTest

var effects: LFStatusEffects
var icon: LFStatusEffectIcon


func before_each() -> void:
	effects = LFStatusEffects.new()
	icon = add_child_autofree(LFStatusEffectIcon.new())


func test_a_timed_effect_drains_with_its_time_left():
	effects.apply(LFStatusEffectDef.new(&'buff', LFStatusEffectDef.Accumulation.INDEPENDENT, 10.0))
	icon.track_effect(effects, &'buff')
	effects.tick(4.0)
	icon._process(0.0)
	assert_almost_eq(icon.fraction, 0.6, 0.001)


func test_refresh_takes_the_time_left_as_the_new_full_length():
	effects.apply(LFStatusEffectDef.new(&'buff', LFStatusEffectDef.Accumulation.SHARED, 10.0))
	icon.track_effect(effects, &'buff')
	effects.tick(5.0)
	icon.refresh()
	effects.tick(2.5)
	icon._process(0.0)
	assert_almost_eq(icon.fraction, 0.5, 0.001)


func test_a_ticking_effect_shows_the_time_to_its_next_tick():
	var def := LFStatusEffectDef.new(&'dot', LFStatusEffectDef.Accumulation.INDEPENDENT, 10.0, 1, LFStatusEffectDef.Overflow.DROP, 2.0, func(_s, _o): pass)
	effects.apply(def)
	icon.track_effect(effects, &'dot')
	effects.tick(0.5)
	icon._process(0.0)
	assert_almost_eq(icon.fraction, 0.75, 0.001)


func test_an_inactive_effect_leaves_the_fraction_alone():
	icon.track_effect(effects, &'gone')
	icon.set_fraction(0.3)
	icon._process(0.0)
	assert_almost_eq(icon.fraction, 0.3, 0.001)


func test_an_untracked_icon_does_nothing():
	icon.set_fraction(0.3)
	icon._process(0.0)
	icon.refresh()
	assert_almost_eq(icon.fraction, 0.3, 0.001)


func test_the_icon_follows_the_effect_without_calling_process_by_hand():
	effects.apply(LFStatusEffectDef.new(&'buff', LFStatusEffectDef.Accumulation.INDEPENDENT, 10.0))
	icon.track_effect(effects, &'buff')
	effects.tick(5.0)
	await wait_process_frames(2)
	assert_almost_eq(icon.fraction, 0.5, 0.001)
