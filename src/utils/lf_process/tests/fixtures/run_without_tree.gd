## Run with `-s` and a marker path after `--`: calls LFProcess.run() under a bare MainLoop
## (no SceneTree) on a command that would create the marker, then prints the result as JSON.
extends MainLoop


func _initialize() -> void:
	var args := OS.get_cmdline_user_args()
	var marker := args[0] if args.size() > 0 else ''
	var result: Variant = await LFProcess.run('/usr/bin/touch', [marker], 2000)
	print('RESULT ' + JSON.stringify(result))


func _process(_delta: float) -> bool:
	return true
