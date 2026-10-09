## Unzips an archive in one awaited call, or builds an [LFZipExtractor] to configure.
##
## [method extract] is the simple path: `await LFZip.extract(zip, folder)`. Use
## [method create_extractor] when you want progress updates, limits or canceling.
class_name LFZip
extends RefCounted


## An extractor for path_to_zip into the directory path_to_extract (with or without a
## trailing slash; res://, user:// or absolute), not yet started. It keeps the default
## limits and overwrite = false.
static func create_extractor(path_to_zip: String, path_to_extract: String) -> LFZipExtractor:
	var extractor := LFZipExtractor.new()
	extractor.path_to_zip = path_to_zip
	extractor.path_to_extract = path_to_extract
	return extractor


## Extracts path_to_zip into path_to_extract with the default limits, awaits the run and
## returns [success, canceled] (two bools). Use it with `await`. [param overwrite] lets
## entries replace files already in the folder. A target the extractor refuses returns
## [false, false] at once. Needs a running SceneTree.
static func extract(path_to_zip: String, path_to_extract: String, overwrite: bool = false) -> Array:
	var extractor := create_extractor(path_to_zip, path_to_extract)
	extractor.overwrite = overwrite
	if !extractor.start():
		return [false, false]
	return await extractor.finished
