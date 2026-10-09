extends GutTest

## Unique names ignoring case, minimum lengths, sign-in that does not say which half was
## wrong, sessions that resume until they expire or are signed out, expired tokens pruned,
## and a file that never holds a password or a raw token.

## Every file this script writes lives in this folder: the process id keeps two runs that
## share one user:// folder apart, and after_each removes it with everything in it.
var scratch_dir := 'user://test-lf-account-store-%d' % OS.get_process_id()
var store_file := scratch_dir + '/accounts.json'

## Owner write only: the file exists but cannot be read.
const WRITE_ONLY := 0x80
## Owner read + write.
const OWNER_READ_WRITE := 0x180
## A stored round count one past the most a store accepts.
const MAX_INT_ROUNDS := LFAccountStore.MAX_STORED_ROUNDS + 1

var store: LFAccountStore
var clock := [1000.0]


func _open() -> LFAccountStore:
	return LFAccountStore.new(store_file, {'rounds': 10}, func(): return clock[0])


func before_each():
	clock[0] = 1000.0
	LFFile.remove(store_file)
	store = _open()


func after_each():
	LFFile.remove_recursive(scratch_dir)


func _stored() -> Dictionary:
	return LFJson.parse_object(FileAccess.get_file_as_string(store_file))


func test_signing_up_opens_a_session_that_resumes():
	var made := store.sign_up('  Hal ', 'open the pod bay')

	assert_false(made.has('error'))
	assert_eq(made['name'], 'Hal', 'the name is trimmed')
	assert_eq(made['token'].length(), 64)
	assert_eq(store.resume(made['token']), {'account_id': made['account_id'], 'name': 'Hal'})


func test_names_are_unique_ignoring_case_and_lengths_are_checked():
	store.sign_up('Hal', 'open the pod bay')

	assert_eq(store.sign_up('hal', 'another long one'), {'error': LFAccountStore.AccountError.NAME_TAKEN})
	assert_eq(store.sign_up('Dave', 'short'), {'error': LFAccountStore.AccountError.PASSWORD_SHORT})
	assert_eq(store.sign_up('X', 'long enough pass'), {'error': LFAccountStore.AccountError.NAME_LENGTH})
	assert_eq(store.sign_up('X'.repeat(25), 'long enough pass'), {'error': LFAccountStore.AccountError.NAME_LENGTH})
	assert_eq(store.count(), 1)


func test_options_override_the_defaults():
	var lax := LFAccountStore.new(store_file, {'min_name': 1, 'min_password': 1, 'rounds': 1, 'token_ttl_seconds': 5.0})
	lax.clock_unix_seconds = func(): return clock[0]

	var made := lax.sign_up('X', 'p')
	assert_false(made.has('error'))
	clock[0] += 6.0
	assert_eq(lax.resume(made['token']), {})


func test_sign_in_never_says_which_half_was_wrong():
	store.sign_up('Hal', 'open the pod bay')

	assert_eq(store.sign_in('Hal', 'wrong'), {'error': LFAccountStore.AccountError.BAD_CREDENTIALS})
	assert_eq(store.sign_in('Nobody', 'open the pod bay'), {'error': LFAccountStore.AccountError.BAD_CREDENTIALS})
	assert_false(store.sign_in(' HAL ', 'open the pod bay').has('error'), 'names ignore case')


func test_a_session_ends_when_it_expires_or_is_signed_out():
	var first := store.sign_up('Hal', 'open the pod bay')
	var second := store.sign_in('Hal', 'open the pod bay')

	assert_true(store.sign_out(first['token']))
	assert_eq(store.resume(first['token']), {})
	assert_false(store.resume(second['token']).is_empty())
	clock[0] += LFAccountStore.DEFAULTS['token_ttl_seconds'] + 1.0
	assert_eq(store.resume(second['token']), {})


func test_signing_out_an_unknown_or_empty_token_changes_nothing():
	store.sign_up('Hal', 'open the pod bay')
	var before := _stored()

	assert_false(store.sign_out('not-a-token'))
	assert_false(store.sign_out(''))
	assert_eq(_stored(), before)
	assert_eq(store.resume(''), {})


func test_accounts_survive_a_restart_and_the_file_holds_no_secrets():
	var made := store.sign_up('Hal', 'open the pod bay')

	var reloaded := _open()

	assert_eq(reloaded.resume(made['token'])['name'], 'Hal')
	assert_false(reloaded.sign_in('Hal', 'open the pod bay').has('error'))
	var stored := FileAccess.get_file_as_string(store_file)
	assert_false(stored.contains('open the pod bay'))
	assert_false(stored.contains(made['token']))


func test_expired_tokens_are_pruned_when_the_file_is_saved():
	var old := store.sign_up('Hal', 'open the pod bay')
	clock[0] += LFAccountStore.DEFAULTS['token_ttl_seconds'] + 1.0

	var fresh := store.sign_in('Hal', 'open the pod bay')

	var tokens: Dictionary = _stored()['tokens']
	assert_eq(tokens.keys(), [fresh['token'].sha256_text()], 'only the live session is kept')
	assert_false(tokens.has(old['token'].sha256_text()))


func test_expired_tokens_are_pruned_after_loading_by_the_clock_set_after_construction():
	store.sign_up('Hal', 'open the pod bay')
	clock[0] += LFAccountStore.DEFAULTS['token_ttl_seconds'] + 1.0
	var reloaded := _open()

	var fresh := reloaded.sign_in('Hal', 'open the pod bay')

	assert_eq(reloaded._data['tokens'].keys(), [fresh['token'].sha256_text()])


## A file in the format from before round counts were stored (fixed clock 1000, hashed
## with LEGACY_ROUNDS) must keep working: the shape, the token hashing and the password
## hashing are a contract. Its first sign-in re-hashes with the store's rounds.
func test_a_file_in_the_stored_format_still_loads():
	var fixture := '{"accounts":{"f5a0341ae6b73a9572cbe169a76ea3fb":{"hash":"3bcd73d9b724d6be9da844d51bd60c520a51a07b3d8f68515196bddc382a5e85","key":"hal","name":"Hal","salt":"e8570d05884aff8929b1cba96c9d7422"}},"tokens":{"57baa9b62471293180a58f9bf88c10be0db8545fd35e66967077b4cbe799379f":{"expires":2593000.0,"id":"f5a0341ae6b73a9572cbe169a76ea3fb"}}}'
	LFFile.save(store_file, fixture)
	var loaded := _open()

	assert_eq(loaded.count(), 1)
	assert_eq(loaded.resume('ea911912266d215909d23472e5b9b2580e0443fc7603941f7feeb06b631f0fcd'), {'account_id': 'f5a0341ae6b73a9572cbe169a76ea3fb', 'name': 'Hal'})
	assert_false(loaded.sign_in('hal', 'open the pod bay').has('error'))
	assert_eq(loaded.sign_up('HAL', 'open the pod bay'), {'error': LFAccountStore.AccountError.NAME_TAKEN})
	var account: Dictionary = _stored()['accounts']['f5a0341ae6b73a9572cbe169a76ea3fb']
	assert_eq(account['rounds'], 10.0, 'the sign-in stored the current rounds')
	assert_eq(account['hash'], LFPasswordHash.compute('open the pod bay', account['salt'], 10))
	assert_false(_open().sign_in('hal', 'open the pod bay').has('error'), 'and the new hash signs in')


func test_the_saved_file_keeps_the_stored_shape():
	var made := store.sign_up('Hal', 'open the pod bay')

	var data := _stored()
	var account: Dictionary = data['accounts'][made['account_id']]
	assert_eq(account.keys().size(), 5)
	assert_eq([account['name'], account['key'], account['rounds']], ['Hal', 'hal', 10.0])
	assert_eq(account['hash'], LFPasswordHash.compute('open the pod bay', account['salt'], 10))
	assert_eq(data['tokens'][made['token'].sha256_text()], {'id': made['account_id'], 'expires': 1000.0 + LFAccountStore.DEFAULTS['token_ttl_seconds']})


func test_a_missing_file_starts_empty_and_is_created_by_the_first_save():
	assert_eq(store.load_state, LFAccountStore.LoadState.NEW)
	assert_false(store.sign_up('Hal', 'open the pod bay').has('error'))
	assert_eq(_open().load_state, LFAccountStore.LoadState.LOADED)


func test_a_malformed_file_is_moved_aside_before_starting_empty():
	for content in ['[1, 2]', '{"accounts": 3, "tokens": "x"}', '{ not json']:
		LFFile.save(store_file, content)
		var odd := _open()

		assert_eq(odd.load_state, LFAccountStore.LoadState.SET_ASIDE, content)
		assert_eq(odd.count(), 0)
		assert_eq(FileAccess.get_file_as_string(odd.set_aside_path), content, 'the old content is kept')
		assert_false(odd.sign_up('Hal', 'open the pod bay').has('error'))
		assert_eq(_stored()['accounts'].size(), 1)
		LFFile.remove(odd.set_aside_path)
		LFFile.remove(store_file)


func test_a_file_of_control_bytes_is_moved_aside_not_read_as_empty():
	for bytes in [PackedByteArray([0, 0, 0]), PackedByteArray([1, 2, 3]), PackedByteArray([0]) + '{"accounts": {}}'.to_utf8_buffer()]:
		LFFile.save_bytes(store_file, bytes)
		var odd := _open()

		assert_eq(odd.load_state, LFAccountStore.LoadState.SET_ASIDE, str(bytes))
		assert_eq(FileAccess.get_file_as_bytes(odd.set_aside_path), bytes, 'the old bytes are kept')
		assert_false(FileAccess.file_exists(store_file))
		LFFile.remove(odd.set_aside_path)


func test_a_whitespace_only_file_still_starts_empty_without_being_moved_aside():
	LFFile.save(store_file, ' \n\t ')
	var blank := _open()

	assert_eq(blank.load_state, LFAccountStore.LoadState.NEW)
	assert_eq(blank.set_aside_path, '')
	assert_true(FileAccess.file_exists(store_file))


func test_an_unreadable_file_is_never_overwritten():
	LFFile.save(store_file, '{"accounts": {}, "tokens": {}}')
	var absolute := LFFile.to_absolute(store_file)
	FileAccess.set_unix_permissions(absolute, WRITE_ONLY)
	if FileAccess.open(store_file, FileAccess.READ) != null:
		FileAccess.set_unix_permissions(absolute, OWNER_READ_WRITE)
		pending('file permissions cannot make a file unreadable here')
		return
	var locked := _open()
	FileAccess.set_unix_permissions(absolute, OWNER_READ_WRITE)

	assert_eq(locked.load_state, LFAccountStore.LoadState.REFUSED)
	assert_false(locked.is_writable())
	assert_eq(locked.sign_up('Hal', 'open the pod bay'), {'error': LFAccountStore.AccountError.STORE_UNAVAILABLE})
	assert_eq(locked.sign_in('Hal', 'open the pod bay'), {'error': LFAccountStore.AccountError.STORE_UNAVAILABLE})
	assert_eq(FileAccess.get_file_as_string(store_file), '{"accounts": {}, "tokens": {}}', 'the file was not touched')
	assert_push_error('could not be read')


func test_a_session_pointing_at_a_malformed_account_does_not_resume():
	var token := 'ea911912266d215909d23472e5b9b2580e0443fc7603941f7feeb06b631f0fcd'
	var session := '{"expires": 1.0e12, "id": "a"}'
	for account in ['5', '{"key": "hal"}']:
		LFFile.save(store_file, '{"accounts": {"a": %s}, "tokens": {"%s": %s}}' % [account, token.sha256_text(), session])
		assert_eq(_open().resume(token), {}, account)


func test_limits_can_be_changed_after_construction():
	store.min_name = 1
	store.max_name = 2
	store.min_password = 2

	assert_false(store.sign_up('X', 'pw').has('error'))
	assert_eq(store.sign_up('XYZ', 'pw'), {'error': LFAccountStore.AccountError.NAME_LENGTH})
	assert_eq(store.sign_up('Y', 'p'), {'error': LFAccountStore.AccountError.PASSWORD_SHORT})

	store.token_ttl_seconds = 1.0
	var made := store.sign_up('Z', 'pw')
	clock[0] += 2.0
	assert_eq(store.resume(made['token']), {})


func test_changing_rounds_keeps_old_hashes_verifying_and_rehashes_them():
	store.sign_up('Hal', 'open the pod bay')
	store.rounds = 11

	assert_false(store.sign_in('Hal', 'open the pod bay').has('error'))
	var account: Dictionary = _stored()['accounts'].values()[0]
	assert_eq(account['rounds'], 11.0)
	assert_eq(account['hash'], LFPasswordHash.compute('open the pod bay', account['salt'], 11))
	assert_eq(store.sign_in('Hal', 'wrong password'), {'error': LFAccountStore.AccountError.BAD_CREDENTIALS})


func test_the_defaults_are_the_documented_ones():
	assert_eq(LFAccountStore.DEFAULTS, {'min_name': 3, 'max_name': 24, 'min_password': 8, 'max_password': 1024, 'max_name_input': 256, 'rounds': 20000, 'legacy_rounds': 20000, 'token_ttl_seconds': 30 * 86400.0, 'max_sessions': 10})
	var plain := LFAccountStore.new(store_file)
	assert_eq(plain.path, store_file)
	assert_eq([plain.min_name, plain.max_name, plain.min_password, plain.max_password, plain.max_name_input, plain.rounds, plain.token_ttl_seconds, plain.max_sessions], [3, 24, 8, 1024, 256, 20000, 30 * 86400.0, 10])
	assert_eq([LFAccountStore.DEFAULT_MIN_NAME, LFAccountStore.DEFAULT_MAX_NAME, LFAccountStore.DEFAULT_MIN_PASSWORD, LFAccountStore.DEFAULT_MAX_PASSWORD, LFAccountStore.DEFAULT_MAX_NAME_INPUT, LFAccountStore.DEFAULT_ROUNDS, LFAccountStore.DEFAULT_TOKEN_TTL_SECONDS, LFAccountStore.DEFAULT_MAX_SESSIONS],
			[3, 24, 8, 1024, 256, 20000, 30 * 86400.0, 10])
	assert_eq(LFAccountStore.LEGACY_ROUNDS, 20000)


func test_the_result_key_constants_name_the_result_keys():
	assert_eq([LFAccountStore.KEY_ACCOUNT_ID, LFAccountStore.KEY_NAME, LFAccountStore.KEY_TOKEN, LFAccountStore.KEY_ERROR], ['account_id', 'name', 'token', 'error'])


func test_changing_the_path_saves_to_the_new_file():
	var other_file := scratch_dir + '/other.json'
	LFFile.remove(other_file)
	store.path = other_file
	store.sign_up('Alice', 'password1')

	assert_false(FileAccess.file_exists(store_file))
	assert_eq(LFAccountStore.new(other_file).count(), 1)
	LFFile.remove(other_file)


func test_hand_edited_entries_with_wrong_types_are_skipped_quietly():
	var token := 'ea911912266d215909d23472e5b9b2580e0443fc7603941f7feeb06b631f0fcd'
	LFFile.save(store_file, '{"accounts": {"a": {"key": 5, "name": "x"}, "b": {"key": ["hal"]}}, "tokens": {"%s": {"expires": [1], "id": "a"}, "t": {"expires": "9e12", "id": "a"}}}' % token.sha256_text())
	var odd := _open()

	assert_eq(odd.sign_in('hal', 'open the pod bay'), {'error': LFAccountStore.AccountError.BAD_CREDENTIALS})
	assert_eq(odd.resume(token), {}, 'a session without a numeric expiry counts as expired')
	assert_false(odd.sign_up('hal', 'open the pod bay').has('error'))
	assert_eq(_stored()['tokens'].size(), 1, 'the malformed sessions were dropped')
	assert_engine_error_count(0)


func test_an_account_without_a_text_name_cannot_sign_in_or_resume():
	var made := store.sign_up('hal', 'open the pod bay')
	var data := _stored()
	var id: String = data['accounts'].keys()[0]
	data['accounts'][id].erase('name')
	LFFile.save_json(store_file, data)
	var odd := _open()

	assert_eq(odd.sign_in('hal', 'open the pod bay'), {'error': LFAccountStore.AccountError.BAD_CREDENTIALS})
	assert_eq(odd.resume(made['token']), {})
	data['accounts'][id]['name'] = [1]
	LFFile.save_json(store_file, data)
	assert_eq(_open().resume(made['token']), {}, 'a name that is not text is not handed out')
	assert_engine_error_count(0)


func test_names_with_control_or_invisible_characters_are_refused():
	for bad in ['Ha\u0001l', 'Ha\nl', 'Ha\u007Fl', 'Ha\u0085l', 'Ha\u00ADl', 'Ha\u200Bl', 'Ha\u200El', 'Ha\u202El', 'Ha\u2060l', 'Ha\u2066l', 'Ha\uFEFFl']:
		assert_eq(store.sign_up(bad, 'open the pod bay'), {'error': LFAccountStore.AccountError.NAME_CHARACTERS}, bad.c_escape())
	assert_false(store.sign_up('Hal 9000', 'open the pod bay').has('error'), 'inner spaces are fine')
	assert_false(store.sign_up('Zoë', 'open the pod bay').has('error'), 'letters beyond ASCII are fine')
	assert_eq(store.count(), 2)


func test_names_that_only_look_like_another_share_its_key():
	var admin := store.sign_up('admin', 'open the pod bay')
	assert_false(admin.has('error'))
	for twin in ['admin ', ' admin', '\u00A0admin\u00A0', 'admin\u2028', '\u3000ADMIN', '\uFF41\uFF44\uFF4D\uFF49\uFF4E', 'ＡＤＭＩＮ']:
		assert_eq(store.sign_up(twin, 'open the pod bay'), {'error': LFAccountStore.AccountError.NAME_TAKEN}, twin.c_escape())
		assert_eq(store.sign_in(twin, 'open the pod bay').get('account_id'), admin['account_id'], twin.c_escape())
	store.sign_up('Hal 9000', 'open the pod bay')
	for spacing in ['Hal\u00A09000', 'Hal  9000', 'hal\u2003\u20039000']:
		assert_eq(store.sign_up(spacing, 'open the pod bay'), {'error': LFAccountStore.AccountError.NAME_TAKEN}, spacing.c_escape())
	assert_eq(store.count(), 2)
	assert_eq(_stored()['accounts'][admin['account_id']]['name'], 'admin', 'the name is kept as typed, trimmed')


func test_invisible_characters_and_names_without_a_letter_are_refused():
	for bad in ['ad\u034Fmin', 'ad\u115Fmin', 'ad\u3164min', 'ad\uFFA0min', 'ad\u2800min', 'ad\u180Emin', 'ad\u17B4min', 'ad\u061Cmin', 'admin\uFE0F', 'admin' + String.chr(0xE0041), 'ad\u2028min',
			'\u3164\u3164\u3164', '\u2800\u2800\u2800', '\u115F\u115F\u115F', '---', '. . .', '___', '\u0301\u0301\u0301']:
		assert_eq(store.sign_up(bad, 'open the pod bay'), {'error': LFAccountStore.AccountError.NAME_CHARACTERS}, bad.c_escape())
	for good in ['Zoë', '007', '１２３', '李小龙', 'Ελένη', 'a_b']:
		assert_false(store.sign_up(good, 'open the pod bay').has('error'), good)
	assert_engine_error_count(0)


func test_what_name_keys_do_not_fold_is_documented_by_these_cases():
	# Cyrillic а, a combining accent and Turkish dotless ı are not folded: no Unicode
	# confusables or normalization data is available, so each is a name of its own.
	assert_ne(LFAccountStore.name_key('аdmin'), LFAccountStore.name_key('admin'))
	assert_ne(LFAccountStore.name_key('café'), LFAccountStore.name_key('cafe\u0301'))
	assert_ne(LFAccountStore.name_key('admın'), LFAccountStore.name_key('admin'))


func test_a_name_filter_option_adds_a_stricter_policy():
	var ascii_only := func(name: String) -> bool:
		for i in name.length():
			if name.unicode_at(i) > 0x7E:
				return false
		return true
	var strict := LFAccountStore.new(store_file, {'rounds': 10, 'name_filter': ascii_only})
	assert_eq(strict.sign_up('аdmin', 'open the pod bay'), {'error': LFAccountStore.AccountError.NAME_CHARACTERS})
	assert_eq(strict.sign_up('Zoë', 'open the pod bay'), {'error': LFAccountStore.AccountError.NAME_CHARACTERS})
	assert_false(strict.sign_up('admin', 'open the pod bay').has('error'))
	strict.name_filter = Callable()
	assert_false(strict.sign_up('Zoë', 'open the pod bay').has('error'), 'cleared, no extra check')


func test_a_stored_round_count_out_of_range_is_refused_without_hashing():
	var salt := 'salt'
	for bad_rounds in [1e308, -5, 0, MAX_INT_ROUNDS]:
		LFFile.save(store_file, JSON.stringify({'accounts': {'a': {'name': 'Hal', 'key': 'hal', 'salt': salt, 'hash': LFPasswordHash.compute('open the pod bay', salt, 3), 'rounds': bad_rounds}}}))
		var damaged := _open()
		var started := Time.get_ticks_msec()
		assert_eq(damaged.sign_in('Hal', 'open the pod bay'), {'error': LFAccountStore.AccountError.BAD_CREDENTIALS}, str(bad_rounds))
		assert_lt(Time.get_ticks_msec() - started, 2000, 'no saturated hash loop')
		assert_push_error('outside 1..')
	LFFile.save_json(store_file, {'accounts': {'a': {'name': 'Hal', 'key': 'hal', 'salt': salt, 'hash': LFPasswordHash.compute('open the pod bay', salt, 3), 'rounds': 3}}})
	assert_false(_open().sign_in('Hal', 'open the pod bay').has('error'), 'an in-range count still works')


func test_each_account_keeps_at_most_max_sessions_dropping_the_soonest_to_expire():
	store.max_sessions = 3
	var first := store.sign_up('Hal', 'open the pod bay')
	var tokens: Array = [first['token']]
	for i in 3:
		clock[0] += 1.0
		tokens.append(store.sign_in('Hal', 'open the pod bay')['token'])

	assert_eq(store.resume(tokens[0]), {}, 'the oldest session ended')
	for token in tokens.slice(1):
		assert_false(store.resume(token).is_empty())
	assert_eq(_stored()['tokens'].size(), 3)
	var other := store.sign_up('Dave', 'open the pod bay')
	assert_false(store.resume(other['token']).is_empty(), 'another account has its own limit')


func test_a_name_lookup_uses_the_index_and_follows_new_accounts():
	store.sign_up('Hal', 'open the pod bay')
	var reloaded := _open()

	assert_eq(reloaded._ids_by_key.keys(), ['hal'])
	reloaded.sign_up('Dave', 'open the pod bay')
	assert_false(reloaded.sign_in('DAVE', 'open the pod bay').has('error'))


func test_a_failed_save_keeps_nothing_and_reports_the_store_unavailable():
	store.sign_up('Hal', 'open the pod bay')
	store.path = scratch_dir + '/dir/'
	DirAccess.make_dir_recursive_absolute(LFFile.to_absolute(store.path))

	assert_eq(store.sign_up('Dave', 'open the pod bay'), {'error': LFAccountStore.AccountError.STORE_UNAVAILABLE})
	assert_eq(store.sign_in('Hal', 'open the pod bay'), {'error': LFAccountStore.AccountError.STORE_UNAVAILABLE})
	assert_eq(store.count(), 1, 'the new account was not kept')
	assert_eq(store._data['tokens'].size(), 1, 'nor the new session')
	assert_push_error_count(2)
	LFFile.remove_recursive(scratch_dir + '/dir')


## A live session whose sign-out cannot be saved: the file still holds it, so after a
## restart it would resume. The sign-out must report failure and keep it live in memory too.
func test_a_sign_out_that_cannot_be_saved_reports_false_and_keeps_the_session():
	var made := store.sign_up('Hal', 'open the pod bay')
	var other := store.sign_up('Dave', 'open the pod bay')
	store.path = scratch_dir + '/dir/'
	DirAccess.make_dir_recursive_absolute(LFFile.to_absolute(store.path))

	assert_false(store.sign_out(made['token']), 'the sign-out was not saved')
	assert_eq(store.resume(made['token']), {'account_id': made['account_id'], 'name': 'Hal'}, 'memory agrees with the file')
	assert_eq(store.resume(other['token'])['name'], 'Dave', 'other sessions are untouched')
	assert_push_error_count(1)
	LFFile.remove_recursive(scratch_dir + '/dir')
	store.path = store_file
	assert_true(store.sign_out(made['token']), 'once the file can be saved, it signs out')
	assert_eq(_open().resume(made['token']), {}, 'and stays signed out after a restart')


## A file written before round counts were stored, by a server that hashed with 5000
## rounds rather than LEGACY_ROUNDS: the caller says so through `legacy_rounds`.
func test_legacy_rounds_can_be_set_for_files_hashed_with_other_rounds():
	var salt := 'a1b2c3'
	LFFile.save_json(store_file, {'accounts': {'acc-1': {'name': 'Hal', 'key': 'hal', 'salt': salt, 'hash': LFPasswordHash.compute('open the pod bay', salt, 5000)}}})

	var default_store := _open()
	assert_eq(default_store.legacy_rounds, LFAccountStore.LEGACY_ROUNDS)
	assert_eq(default_store.sign_in('hal', 'open the pod bay'), {'error': LFAccountStore.AccountError.BAD_CREDENTIALS}, 'checked with LEGACY_ROUNDS by default')

	var configured := LFAccountStore.new(store_file, {'rounds': 10, 'legacy_rounds': 5000})
	configured.clock_unix_seconds = func(): return clock[0]
	assert_eq(configured.legacy_rounds, 5000)
	assert_false(configured.sign_in('hal', 'open the pod bay').has('error'))
	assert_eq(_stored()['accounts']['acc-1']['rounds'], 10.0, 'and re-hashed with the current rounds')


func test_a_file_holding_only_whitespace_starts_empty_like_a_missing_one():
	LFFile.save(store_file, '  \n\t ')
	var blank := _open()

	assert_eq(blank.load_state, LFAccountStore.LoadState.NEW)
	assert_eq(blank.set_aside_path, '', 'nothing was moved aside')
	assert_false(blank.sign_up('Hal', 'open the pod bay').has('error'))
	assert_eq(_stored()['accounts'].size(), 1, 'the first save replaced it')


## A malformed file in a folder the store may read but not write: it cannot be moved
## aside, so it must be left exactly as it is and the store must refuse every change.
func test_a_malformed_file_that_cannot_be_moved_aside_is_never_overwritten():
	var locked_dir := scratch_dir + '/locked'
	var locked_file := locked_dir + '/accounts.json'
	const OWNER_READ_EXECUTE := 0x140
	const OWNER_ALL := 0x1C0
	DirAccess.make_dir_recursive_absolute(LFFile.to_absolute(locked_dir))
	LFFile.save(locked_file, '[1, 2]')
	FileAccess.set_unix_permissions(LFFile.to_absolute(locked_dir), OWNER_READ_EXECUTE)
	if FileAccess.open(locked_dir + '/probe', FileAccess.WRITE) != null:
		FileAccess.set_unix_permissions(LFFile.to_absolute(locked_dir), OWNER_ALL)
		LFFile.remove_recursive(locked_dir)
		pending('folder permissions cannot stop a rename here')
		return
	var stuck := LFAccountStore.new(locked_file, {'rounds': 10})
	FileAccess.set_unix_permissions(LFFile.to_absolute(locked_dir), OWNER_ALL)

	assert_eq(stuck.load_state, LFAccountStore.LoadState.REFUSED)
	assert_eq(stuck.set_aside_path, '')
	assert_eq(stuck.sign_up('Hal', 'open the pod bay'), {'error': LFAccountStore.AccountError.STORE_UNAVAILABLE})
	assert_eq(stuck.resume('anything'), {})
	assert_false(stuck.sign_out('anything'))
	assert_eq(FileAccess.get_file_as_string(locked_file), '[1, 2]', 'the file was not touched')
	assert_push_error('could not be moved aside')
	LFFile.remove_recursive(locked_dir)


func test_a_max_sessions_below_one_still_keeps_the_newest_session():
	store.max_sessions = 0
	var first := store.sign_up('Hal', 'open the pod bay')
	clock[0] += 1.0
	var second := store.sign_in('Hal', 'open the pod bay')

	assert_eq(store.resume(first['token']), {}, 'the older one ended')
	assert_eq(store.resume(second['token'])['name'], 'Hal')


func test_when_two_accounts_share_a_name_the_first_in_the_file_wins():
	var salt := 's'
	LFFile.save_json(store_file, {'accounts': {
		'first': {'name': 'Hal', 'key': 'hal', 'salt': salt, 'hash': LFPasswordHash.compute('first password', salt, 10), 'rounds': 10},
		'second': {'name': 'HAL', 'key': 'hal', 'salt': salt, 'hash': LFPasswordHash.compute('second password', salt, 10), 'rounds': 10},
	}})
	var loaded := _open()

	assert_eq(loaded.sign_in('hal', 'first password')['account_id'], 'first')
	assert_eq(loaded.sign_in('hal', 'second password'), {'error': LFAccountStore.AccountError.BAD_CREDENTIALS})


func test_a_hand_edited_non_number_rounds_is_checked_with_legacy_rounds():
	var salt := 's'
	LFFile.save_json(store_file, {'accounts': {'a': {'name': 'Hal', 'key': 'hal', 'salt': salt, 'hash': LFPasswordHash.compute('open the pod bay', salt, 7), 'rounds': 'many'}}})
	var loaded := LFAccountStore.new(store_file, {'rounds': 10, 'legacy_rounds': 7})
	loaded.clock_unix_seconds = func(): return clock[0]

	assert_false(loaded.sign_in('hal', 'open the pod bay').has('error'))
	assert_eq(_stored()['accounts']['a']['rounds'], 10.0, 'and re-hashed with a real count')


func test_a_sign_in_with_unchanged_rounds_keeps_the_salt_and_hash():
	var made := store.sign_up('Hal', 'open the pod bay')
	var before: Dictionary = _stored()['accounts'][made['account_id']]

	store.sign_in('Hal', 'open the pod bay')

	assert_eq(_stored()['accounts'][made['account_id']], before, 'no second hash, nothing rewritten')


## A sign-in that would re-hash with new rounds but cannot be saved must leave the account
## as the file still has it, or the next restart would disagree with memory.
func test_a_rehash_that_cannot_be_saved_leaves_the_account_as_it_was():
	var made := store.sign_up('Hal', 'open the pod bay')
	var before: Dictionary = store._data['accounts'][made['account_id']].duplicate()
	store.rounds = 11
	store.path = scratch_dir + '/dir/'
	DirAccess.make_dir_recursive_absolute(LFFile.to_absolute(store.path))

	assert_eq(store.sign_in('Hal', 'open the pod bay'), {'error': LFAccountStore.AccountError.STORE_UNAVAILABLE})
	assert_eq(store._data['accounts'][made['account_id']], before)
	assert_push_error_count(1)
	LFFile.remove_recursive(scratch_dir + '/dir')
	store.path = store_file
	assert_false(store.sign_in('Hal', 'open the pod bay').has('error'), 'the old hash still signs in')


## At max_sessions, a new session first ends the soonest-expiring one; when the new one
## cannot be saved, the ended one must come back.
func test_a_session_ended_to_make_room_returns_when_the_new_one_cannot_be_saved():
	store.max_sessions = 1
	var made := store.sign_up('Hal', 'open the pod bay')
	store.path = scratch_dir + '/dir/'
	DirAccess.make_dir_recursive_absolute(LFFile.to_absolute(store.path))

	assert_eq(store.sign_in('Hal', 'open the pod bay'), {'error': LFAccountStore.AccountError.STORE_UNAVAILABLE})
	assert_eq(store.resume(made['token'])['name'], 'Hal', 'the old session is live again')
	assert_push_error_count(1)
	LFFile.remove_recursive(scratch_dir + '/dir')


func test_a_session_lives_until_its_expiry_and_an_expired_resume_saves_it_away():
	var made := store.sign_up('Hal', 'open the pod bay')
	clock[0] += LFAccountStore.DEFAULT_TOKEN_TTL_SECONDS

	assert_eq(store.resume(made['token'])['name'], 'Hal', 'still live at the expiry second itself')
	clock[0] += 1.0
	assert_eq(store.resume(made['token']), {})
	assert_eq(_stored()['tokens'], {}, 'the expired session was dropped from the file')


func test_rounds_set_below_one_still_make_accounts_that_can_sign_in():
	for low in [0, -7]:
		var fresh := _open()
		fresh.rounds = low
		var name := 'Hal%d' % absi(low)
		assert_false(fresh.sign_up(name, 'open the pod bay').has('error'))
		assert_eq(_stored()['accounts'].values().filter(func(a): return a['name'] == name)[0]['rounds'], 1, 'stored within the accepted range')
		assert_false(fresh.sign_in(name, 'open the pod bay').has('error'), 'rounds %d' % low)


func test_a_name_padded_past_the_input_cap_is_refused_in_sign_up_and_sign_in_without_hashing():
	store.sign_up('Hal', 'open the pod bay')
	var padded := ' '.repeat(150) + 'Hal' + ' '.repeat(147)

	var started := Time.get_ticks_usec()
	var up := store.sign_up(padded, 'open the pod bay')
	var in_ := store.sign_in(padded, 'open the pod bay')
	var elapsed_ms := (Time.get_ticks_usec() - started) / 1000.0

	assert_eq(up['error'], LFAccountStore.AccountError.NAME_LENGTH)
	assert_eq(in_['error'], LFAccountStore.AccountError.BAD_CREDENTIALS)
	assert_lt(elapsed_ms, 5.0, 'no password was hashed')


func test_a_name_padded_to_200_characters_still_works():
	var padded := ' '.repeat(98) + 'Hal' + ' '.repeat(99)
	assert_eq(padded.length(), 200)

	assert_eq(store.sign_up(padded, 'open the pod bay')['name'], 'Hal')
	assert_false(store.sign_in(padded, 'open the pod bay').has('error'))


func test_a_password_over_the_cap_is_too_long_at_sign_up_and_bad_credentials_at_sign_in():
	var longest := 'a'.repeat(LFAccountStore.DEFAULT_MAX_PASSWORD)
	assert_false(store.sign_up('Hal', longest).has('error'), 'a password at the cap is fine')
	var too_long := longest + 'a'

	assert_eq(store.sign_up('Dave', too_long)['error'], LFAccountStore.AccountError.PASSWORD_LONG)
	assert_eq(store.sign_in('Hal', too_long)['error'], LFAccountStore.AccountError.BAD_CREDENTIALS)
	assert_eq(LFAccountStore.AccountError.PASSWORD_LONG, LFAccountStore.AccountError.STORE_UNAVAILABLE + 1, 'appended after the existing errors')


func test_a_cap_of_zero_or_less_means_unlimited():
	for cap in [0, -1]:
		var open := LFAccountStore.new(store_file, {'rounds': 10, 'max_password': cap, 'max_name_input': cap})
		var padded := ' '.repeat(400) + 'Hal%d' % absi(cap) + ' '.repeat(400)
		var password := 'a'.repeat(5000)
		assert_false(open.sign_up(padded, password).has('error'), 'cap %d' % cap)
		assert_false(open.sign_in(padded, password).has('error'), 'cap %d' % cap)


func test_a_max_password_below_min_password_is_raised_to_it():
	var open := LFAccountStore.new(store_file, {'rounds': 10, 'min_password': 8, 'max_password': 4})

	assert_false(open.sign_up('Hal', 'a'.repeat(8)).has('error'), 'min_password still fits')
	assert_eq(open.sign_up('Dave', 'a'.repeat(9))['error'], LFAccountStore.AccountError.PASSWORD_LONG)
	assert_false(open.sign_in('Hal', 'a'.repeat(8)).has('error'))


class ClockHolder:
	extends Object
	func now() -> float:
		return 1000.0


func test_a_freed_clock_makes_sessions_expired_and_opens_none():
	var holder := ClockHolder.new()
	store.clock_unix_seconds = holder.now
	var made := store.sign_up('Hal', 'open the pod bay')
	assert_false(made.has('error'))
	assert_false(store.resume(made['token']).is_empty())
	holder.free()

	assert_eq(store.resume(made['token']), {}, 'fails closed rather than never expiring')
	assert_eq(store.sign_up('Dave', 'open the pod bay'), {'error': LFAccountStore.AccountError.STORE_UNAVAILABLE})
	assert_eq(store.sign_in('Hal', 'open the pod bay'), {'error': LFAccountStore.AccountError.STORE_UNAVAILABLE})
	assert_push_error_count(1, 'reported once')


func test_a_freed_clock_does_not_wipe_persisted_sessions_from_the_file():
	var holder := ClockHolder.new()
	store.clock_unix_seconds = holder.now
	var hal := store.sign_up('Hal', 'open the pod bay')
	var dave := store.sign_up('Dave', 'open the pod bay')
	assert_false(hal.has('error') or dave.has('error'))
	holder.free()

	assert_eq(store.resume(hal['token']), {}, 'fails closed in memory')
	assert_true(store.sign_out(dave['token']), 'a save happens while the clock is dead')
	assert_push_error_count(1, 'reported once')

	var reloaded := LFAccountStore.new(store_file, {'rounds': 10}, func(): return 1000.0)
	assert_eq(reloaded.resume(hal['token'])['name'], 'Hal', 'the persisted session survived the save')
	assert_eq(reloaded.resume(dave['token']), {}, 'the signed-out one is gone')


func test_an_unknown_option_key_is_reported_once_naming_it():
	var configured := LFAccountStore.new(store_file, {'rounds': 10, 'min_pasword': 3, 'name_filter': Callable()})

	assert_push_error('min_pasword')
	assert_eq(configured.min_password, LFAccountStore.DEFAULT_MIN_PASSWORD, 'the misspelt key changed nothing')


func test_known_option_keys_and_a_name_filter_report_nothing():
	LFAccountStore.new(store_file, {'rounds': 10, 'token_ttl_seconds': 60.0, 'name_filter': func(_n): return true})

	assert_push_error_count(0)


func test_the_clock_can_be_given_to_the_constructor_and_replaced_later():
	var opened := LFAccountStore.new(store_file, {'rounds': 10}, func(): return 5.0)
	assert_eq(opened.clock_unix_seconds.call(), 5.0)
	var default_clock := LFAccountStore.new(store_file, {'rounds': 10})
	assert_almost_eq(float(default_clock.clock_unix_seconds.call()), Time.get_unix_time_from_system(), 5.0)


func test_a_nan_token_ttl_is_rejected_and_the_value_is_kept():
	var configured := LFAccountStore.new(store_file, {'rounds': 10, 'token_ttl_seconds': NAN})
	assert_push_error_count(1)
	assert_eq(configured.token_ttl_seconds, LFAccountStore.DEFAULT_TOKEN_TTL_SECONDS)
	configured.token_ttl_seconds = 60.0
	configured.token_ttl_seconds = NAN
	assert_push_error_count(2)
	assert_eq(configured.token_ttl_seconds, 60.0)
