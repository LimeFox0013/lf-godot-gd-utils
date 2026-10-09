## Stores user accounts (a name and a password) and their login sessions in one JSON file.
##
## A password is never stored, only an `LFPasswordHash` of it with a per-account salt (a
## random string mixed into the hash so equal passwords hash differently) and the round
## count it was made with. Signing in hands back a random session token the caller keeps
## instead of the password, and only a SHA-256 of each token is stored. Names are unique
## ignoring case, surrounding whitespace, the width of fullwidth ASCII and how many
## whitespace characters separate words (see `name_key`); look-alike letters from other
## scripts and Unicode normalization forms are not detected.
##
## Results are Dictionaries: a session is `{account_id, name, token}`, a failure is
## `{error: AccountError}`, so the caller words the message itself. A wrong name and a wrong
## password are the same `BAD_CREDENTIALS`. Both take one hash: an unknown name is hashed
## with `rounds`, a known one with the rounds its account was hashed with. While every
## account uses `rounds` (each is re-hashed with them on its next successful sign-in) the
## two take the same time; an account still on other rounds answers in a different time,
## which can tell a guesser that the name exists.
##
## The file is `{accounts: {id: {name, key, salt, hash, rounds}}, tokens: {token_sha256:
## {id, expires}}}`, where `key` is the name's `name_key` and `expires` is in `clock_unix_seconds`
## seconds. An account without `rounds` (a file from before it was stored) is checked
## with `legacy_rounds`. Expired tokens are dropped before the first use after loading and
## whenever the file is saved. Every save rewrites the whole file, on the calling thread.
##
## An existing file this store cannot use is never overwritten: content that is not a JSON
## object in the expected shape is first moved aside (see `load_state`), and a file that
## cannot be read (or moved aside) leaves the store refusing every change.
class_name LFAccountStore
extends RefCounted

## Why a sign-up or sign-in failed.
enum AccountError {
	## The trimmed name is shorter than `min_name` or longer than `max_name`.
	NAME_LENGTH,
	## The password is shorter than `min_password`.
	PASSWORD_SHORT,
	## Another account has this name, ignoring case.
	NAME_TAKEN,
	## No such name, or the wrong password.
	BAD_CREDENTIALS,
	## The name holds a control or invisible character, has no letter or digit (see
	## `is_valid_name_text`), or `name_filter` refused it.
	NAME_CHARACTERS,
	## The accounts file could not be read when the store was created, or the change could
	## not be saved; nothing was changed. See `load_state`.
	STORE_UNAVAILABLE,
	## The password is longer than `max_password`. Only `sign_up` says so; `sign_in` answers
	## `BAD_CREDENTIALS`.
	PASSWORD_LONG,
}

## What the constructor found at `path`.
enum LoadState {
	## No file, or an empty one: the store starts empty and the first save creates it.
	NEW,
	## The file was loaded.
	LOADED,
	## The file was not a JSON object in the expected shape. It was moved to
	## `set_aside_path` (so nothing in it is lost) and the store started empty.
	SET_ASIDE,
	## The file exists but could not be read, or was malformed and could not be moved
	## aside. The store holds no accounts and never writes the file: every sign-up and
	## sign-in returns `STORE_UNAVAILABLE`.
	REFUSED,
}

## Default shortest name, after trimming.
const DEFAULT_MIN_NAME := 3
## Default longest name, after trimming.
const DEFAULT_MAX_NAME := 24
## Default shortest password.
const DEFAULT_MIN_PASSWORD := 8
## Default longest password (a value of 0 or less in `max_password` means no cap).
const DEFAULT_MAX_PASSWORD := 1024
## Default longest name as typed, before trimming (0 or less in `max_name_input` means no
## cap).
const DEFAULT_MAX_NAME_INPUT := 256
## Default `LFPasswordHash` rounds for new hashes. About 25 ms per hash on an Apple-silicon
## laptop; see the README for how that compares with password-hashing guidance.
const DEFAULT_ROUNDS := 20000
## Default `legacy_rounds`: the rounds this store hashed with before it stored a round
## count per account.
const LEGACY_ROUNDS := 20000
## Most rounds a stored account may claim (about 6 s of hashing at the measured 25 ms per
## 20,000). An account whose stored `rounds` is not between 1 and this is refused at
## sign-in rather than hashed, so a corrupted file cannot stall the server.
const MAX_STORED_ROUNDS := 5000000
## Default session lifetime in seconds (30 days).
const DEFAULT_TOKEN_TTL_SECONDS := 30 * 86400.0
## Default most live sessions one account keeps; a new one beyond it ends the session
## that expires soonest.
const DEFAULT_MAX_SESSIONS := 10

## Result key: the signed-in account's id.
const KEY_ACCOUNT_ID := 'account_id'
## Result key: the account's name.
const KEY_NAME := 'name'
## Result key: the session token to keep instead of the password.
const KEY_TOKEN := 'token'
## Result key: the `AccountError` of a failed sign-up or sign-in.
const KEY_ERROR := 'error'

## Option key (and constructor `options` key): shortest name.
const _OPT_MIN_NAME := 'min_name'
## Option key: longest name.
const _OPT_MAX_NAME := 'max_name'
## Option key: shortest password.
const _OPT_MIN_PASSWORD := 'min_password'
## Option key: longest password.
const _OPT_MAX_PASSWORD := 'max_password'
## Option key: longest name as typed, before trimming.
const _OPT_MAX_NAME_INPUT := 'max_name_input'
## Option key: hash rounds.
const _OPT_ROUNDS := 'rounds'
## Option key: rounds of accounts that store none.
const _OPT_LEGACY_ROUNDS := 'legacy_rounds'
## Option key: session lifetime in seconds.
const _OPT_TOKEN_TTL_SECONDS := 'token_ttl_seconds'
## Option key: most live sessions per account.
const _OPT_MAX_SESSIONS := 'max_sessions'
## Option key: the extra name check (not in DEFAULTS; none by default).
const _OPT_NAME_FILTER := 'name_filter'

## File key: the accounts by id.
const _FILE_ACCOUNTS := 'accounts'
## File key: the sessions by token SHA-256.
const _FILE_TOKENS := 'tokens'
## Account field: the trimmed name as typed.
const _FIELD_NAME := 'name'
## Account field: the name's `name_key`, for unique lookups.
const _FIELD_KEY := 'key'
## Account field: the per-account salt.
const _FIELD_SALT := 'salt'
## Account field: the password hash.
const _FIELD_HASH := 'hash'
## Account field: the rounds the hash was made with.
const _FIELD_ROUNDS := 'rounds'
## Session field: the account id.
const _FIELD_ID := 'id'
## Session field: the expiry time in `clock_unix_seconds` seconds.
const _FIELD_EXPIRES := 'expires'

## Random bytes in a new account id (`LFUuid.token`: twice as many hex characters).
const _ACCOUNT_ID_LENGTH := 16
## Random bytes in a new salt (twice as many hex characters).
const _SALT_LENGTH := 16
## Random bytes in a new session token (twice as many hex characters).
const _SESSION_TOKEN_LENGTH := 32
## Salt hashed against for an unknown name, so it costs as much as a real check.
const _DUMMY_SALT := 'unknown'
## Tag of a malformed file's backup: `<file>.corrupt-<unix time>`.
const _CORRUPT_TAG := 'corrupt'
## Log line prefix.
const _LOG_PREFIX := '[LFAccountStore]'
## Characters of a bad stored round count shown in the error (1e308 prints 309 digits).
const _ROUNDS_SHOWN := 24

## Code points `is_valid_name_text` refuses, as inclusive [first, last] ranges: C0
## controls, DEL and C1 controls, then every range Unicode lists as
## Default_Ignorable_Code_Point (the soft hyphen, the combining grapheme joiner, the Arabic
## letter mark, the Hangul fillers, the Khmer inherent vowels, the Mongolian variation
## selectors and vowel separator, zero-width spaces, joiners and direction marks,
## bidirectional embeddings, overrides and isolates, invisible operators, variation
## selectors, the byte-order mark, the halfwidth Hangul filler, the shorthand format
## controls, the musical format controls and the tags block), plus the line and paragraph
## separators inside a name, the blank Braille pattern, the interlinear annotation
## characters, lone surrogate halves and values above U+10FFFF.
const _FORBIDDEN_RANGES: Array[Vector2i] = [
	Vector2i(0x0000, 0x001F),
	Vector2i(0x007F, 0x009F),
	Vector2i(0x00AD, 0x00AD),
	Vector2i(0x034F, 0x034F),
	Vector2i(0x061C, 0x061C),
	Vector2i(0x115F, 0x1160),
	Vector2i(0x17B4, 0x17B5),
	Vector2i(0x180B, 0x180F),
	Vector2i(0x200B, 0x200F),
	Vector2i(0x2028, 0x2029),
	Vector2i(0x202A, 0x202E),
	Vector2i(0x2060, 0x206F),
	Vector2i(0x2800, 0x2800),
	Vector2i(0x3164, 0x3164),
	Vector2i(0xD800, 0xDFFF),
	Vector2i(0xFE00, 0xFE0F),
	Vector2i(0xFEFF, 0xFEFF),
	Vector2i(0xFFA0, 0xFFA0),
	Vector2i(0xFFF0, 0xFFFB),
	Vector2i(0x1BCA0, 0x1BCA3),
	Vector2i(0x1D173, 0x1D17A),
	Vector2i(0xE0000, 0xE0FFF),
	Vector2i(0x110000, 0x7FFFFFFF),
]

## Code points trimmed from both ends of a name, and folded to one space inside its
## `name_key`: the Unicode White_Space characters (ASCII whitespace, U+0085, the no-break
## space U+00A0, U+1680, the spaces U+2000–U+200A, the line and paragraph separators
## U+2028–U+2029, U+202F, U+205F and the ideographic space U+3000).
const _WHITESPACE_RANGES: Array[Vector2i] = [
	Vector2i(0x0009, 0x000D),
	Vector2i(0x0020, 0x0020),
	Vector2i(0x0085, 0x0085),
	Vector2i(0x00A0, 0x00A0),
	Vector2i(0x1680, 0x1680),
	Vector2i(0x2000, 0x200A),
	Vector2i(0x2028, 0x2029),
	Vector2i(0x202F, 0x202F),
	Vector2i(0x205F, 0x205F),
	Vector2i(0x3000, 0x3000),
]
## Fullwidth form of `!`, the first fullwidth ASCII character.
const _FULLWIDTH_FIRST := 0xFF01
## Fullwidth form of `~`, the last fullwidth ASCII character.
const _FULLWIDTH_LAST := 0xFF5E
## Subtracted from a fullwidth form to get its ASCII character.
const _FULLWIDTH_OFFSET := 0xFEE0
## `0`, the first ASCII digit a name may show instead of a letter.
const _DIGIT_ZERO := 0x30
## `9`, the last ASCII digit.
const _DIGIT_NINE := 0x39
## The underscore, which counts as an identifier start but is not a letter.
const _UNDERSCORE := 0x5F
## The space each run of whitespace inside a `name_key` becomes.
const _SPACE := ' '

## Default options; any of them can be overridden through the constructor's `options`:
## `min_name` 3, `max_name` 24, `min_password` 8, `max_password` 1024, `max_name_input` 256,
## `rounds` 20000, `legacy_rounds` 20000,
## `token_ttl_seconds` 30 days and `max_sessions` 10.
const DEFAULTS := {
	_OPT_MIN_NAME: DEFAULT_MIN_NAME,
	_OPT_MAX_NAME: DEFAULT_MAX_NAME,
	_OPT_MIN_PASSWORD: DEFAULT_MIN_PASSWORD,
	_OPT_MAX_PASSWORD: DEFAULT_MAX_PASSWORD,
	_OPT_MAX_NAME_INPUT: DEFAULT_MAX_NAME_INPUT,
	_OPT_ROUNDS: DEFAULT_ROUNDS,
	_OPT_LEGACY_ROUNDS: LEGACY_ROUNDS,
	_OPT_TOKEN_TTL_SECONDS: DEFAULT_TOKEN_TTL_SECONDS,
	_OPT_MAX_SESSIONS: DEFAULT_MAX_SESSIONS,
}

## The JSON file the accounts are saved to. Changing it makes later saves go to the new
## file; it does not reload, and it does not lift a `REFUSED` state.
var path: String
## Shortest allowed name, after trimming.
var min_name: int
## Longest allowed name, after trimming.
var max_name: int
## Shortest allowed password.
var min_password: int
## Longest allowed password, in characters. 0 or less means no cap; a value below
## `min_password` is used as `min_password`. Lowering it locks out accounts whose password is
## longer, since `sign_in` refuses an over-long password without checking it.
var max_password: int
## Longest allowed name as typed, before `trim_name`, in characters. 0 or less means no cap.
## It bounds the work `sign_up` and `sign_in` do on a name padded with whitespace.
var max_name_input: int
## Extra check a new name must pass, after the built-in ones: called with the trimmed name,
## returns `true` to accept it; a refused name fails `sign_up` with `NAME_CHARACTERS`.
## Empty (the default) checks nothing more. Set it through the `name_filter` option or
## here, e.g. to allow only ASCII names (see the README).
var name_filter: Callable = Callable()
## `LFPasswordHash` rounds for new hashes. Each account stores the rounds its hash was made
## with, so changing this locks out no account that stores them: an account hashed with
## other rounds is checked with its own, and re-hashed with these on its next successful
## sign-in. An account that stores none is checked with `legacy_rounds`. A value outside
## 1..`MAX_STORED_ROUNDS` is used as the nearest limit.
var rounds: int
## Rounds an account without a stored round count is checked with: one from a file written
## before the count was stored. It must equal the rounds that file's hashes were made with
## (`LEGACY_ROUNDS` for files this class wrote), or those accounts cannot sign in.
var legacy_rounds: int
## Seconds a new session token lives ("TTL", time to live). Tokens already handed out
## keep the expiry they were given. A NaN is rejected: reported as an error, and the value is
## kept (a NaN expiry would never pass).
var token_ttl_seconds: float:
	get:
		return _token_ttl_seconds
	set(value):
		if is_nan(value):
			_log.error('token_ttl_seconds is NaN; rejected, keeping %s' % _token_ttl_seconds)
			return
		_token_ttl_seconds = value
## Most live sessions one account keeps (at least 1 is kept). Opening one more ends the
## session that expires soonest.
var max_sessions: int
## Unix seconds now, the clock token expiry is measured on and written to disk with;
## `Time.get_unix_time_from_system` by default. Replaceable (tests, a simulated clock).
var clock_unix_seconds: Callable
## What the constructor found at `path` (see `LoadState`).
var load_state: LoadState = LoadState.NEW
## Where a malformed file was moved when `load_state` is `SET_ASIDE`; "" otherwise.
var set_aside_path: String = ''

var _token_ttl_seconds := DEFAULT_TOKEN_TTL_SECONDS
var _data: Dictionary = {}
var _pruned := false
## Lower-cased name -> account id, so a lookup does not scan every account.
var _ids_by_key: Dictionary = {}
## Account id -> Array of its token hashes; rebuilt by every prune.
var _tokens_by_account: Dictionary = {}
var _log := LFLogger.new([_LOG_PREFIX])
var _clock_error_reported := false


## Loads the accounts from `file_path`. A missing, empty or whitespace-only file starts empty. Content that
## is not a JSON object (a file of control bytes such as zero bytes included), or whose `accounts` or `tokens` is not an object, is moved to
## `<file>.corrupt-<unix time>` with a pushed warning before starting empty. A file that
## exists but cannot be read, or cannot be moved aside, is left alone and the store refuses
## every change (`load_state` is `REFUSED`, with a pushed error).
## `options` overrides any of `DEFAULTS` and may set `name_filter` (a Callable, see the
## property). An unknown key is ignored and reported once through `LFLogger` as an error
## naming it. `initial_clock_unix_seconds` sets `clock_unix_seconds`; without it the Unix
## time is used.
func _init(file_path: String, options: Dictionary = {}, initial_clock_unix_seconds := Callable()) -> void:
	path = file_path
	clock_unix_seconds = initial_clock_unix_seconds if not initial_clock_unix_seconds.is_null() else Time.get_unix_time_from_system
	_report_unknown_options(options)
	var settings := DEFAULTS.merged(options, true)
	min_name = int(settings[_OPT_MIN_NAME])
	max_name = int(settings[_OPT_MAX_NAME])
	min_password = int(settings[_OPT_MIN_PASSWORD])
	max_password = int(settings[_OPT_MAX_PASSWORD])
	max_name_input = int(settings[_OPT_MAX_NAME_INPUT])
	rounds = int(settings[_OPT_ROUNDS])
	legacy_rounds = int(settings[_OPT_LEGACY_ROUNDS])
	token_ttl_seconds = float(settings[_OPT_TOKEN_TTL_SECONDS])
	max_sessions = int(settings[_OPT_MAX_SESSIONS])
	var filter: Variant = options.get(_OPT_NAME_FILTER)
	if filter is Callable:
		name_filter = filter
	_load()


## Reports each key of `options` that is not a setting, once, naming it.
func _report_unknown_options(options: Dictionary) -> void:
	for key: Variant in options:
		if key != _OPT_NAME_FILTER and not DEFAULTS.has(key):
			_log.error('unknown option "%s" ignored' % str(key))


## Returns `true` when the store can save changes: `load_state` is not `REFUSED`.
func is_writable() -> bool:
	return load_state != LoadState.REFUSED


## Returns `true` when `name` holds none of the characters account names refuse (control
## characters, every Unicode Default_Ignorable_Code_Point, the line and paragraph
## separators, the blank Braille pattern U+2800, U+FFF9–U+FFFB and lone surrogates; see
## the README for the full list) and shows at least one letter (a Unicode identifier
## start other than `_`) or ASCII digit, fullwidth forms counted as their ASCII
## characters. So a name made only of spaces, punctuation or invisible fillers is refused.
## Look-alike letters from other scripts (Cyrillic `а` for Latin `a`), combining marks and
## Unicode normalization forms are not detected.
static func is_valid_name_text(name: String) -> bool:
	var shows_letter := false
	for i in name.length():
		var code := _fold_width(name.unicode_at(i))
		if _in_ranges(code, _FORBIDDEN_RANGES):
			return false
		if not shows_letter:
			shows_letter = (code >= _DIGIT_ZERO and code <= _DIGIT_NINE) \
				or (code != _UNDERSCORE and name.substr(i, 1).is_valid_unicode_identifier())
	return shows_letter


## The key two names must not share: `name` trimmed of Unicode whitespace (see
## `trim_name`), each run of whitespace inside it made one space, fullwidth ASCII forms
## (U+FF01–U+FF5E) made ASCII, then lower-cased. So "Admin", " admin\u00A0" and
## "ａｄｍｉｎ" share the key "admin". Cyrillic "аdmin", "admín" spelled with a combining
## accent and other look-alikes keep keys of their own.
static func name_key(name: String) -> String:
	var parts := PackedStringArray()
	var in_space := false
	var trimmed := trim_name(name)
	for i in trimmed.length():
		var code := trimmed.unicode_at(i)
		if _in_ranges(code, _WHITESPACE_RANGES):
			if not in_space:
				parts.append(_SPACE)
			in_space = true
			continue
		in_space = false
		var folded := _fold_width(code)
		# Characters are copied, not rebuilt from code points, so nothing is re-decoded.
		parts.append(String.chr(folded) if folded != code else trimmed.substr(i, 1))
	return ''.join(parts).to_lower()


## `name` without the Unicode whitespace at either end (ASCII whitespace, the no-break
## space, the line and paragraph separators, the ideographic space and the other
## White_Space characters), where `String.strip_edges` trims ASCII only.
static func trim_name(name: String) -> String:
	var first := 0
	var last := name.length() - 1
	while first <= last and _in_ranges(name.unicode_at(first), _WHITESPACE_RANGES):
		first += 1
	while last >= first and _in_ranges(name.unicode_at(last), _WHITESPACE_RANGES):
		last -= 1
	return name.substr(first, last - first + 1)


static func _in_ranges(code: int, ranges: Array[Vector2i]) -> bool:
	for range_ in ranges:
		if code >= range_.x and code <= range_.y:
			return true
	return false


## The ASCII character of a fullwidth form; any other code point unchanged.
static func _fold_width(code: int) -> int:
	if code >= _FULLWIDTH_FIRST and code <= _FULLWIDTH_LAST:
		return code - _FULLWIDTH_OFFSET
	return code


## Creates an account and signs it in: `{account_id, name, token}` (the name trimmed by
## `trim_name`), or `{error}` with `NAME_LENGTH` (also when the name as typed is longer than
## `max_name_input`; checked before trimming), `PASSWORD_LONG` (longer than `max_password`), `NAME_CHARACTERS` (see
## `is_valid_name_text` and `name_filter`), `PASSWORD_SHORT`, `NAME_TAKEN` (another account
## has the same `name_key`) or `STORE_UNAVAILABLE` (nothing is kept when the file cannot
## be saved). Saves the file.
func sign_up(name: String, password: String) -> Dictionary:
	if not is_writable():
		return {KEY_ERROR: AccountError.STORE_UNAVAILABLE}
	_prune_once()
	if _over(name.length(), max_name_input):
		return {KEY_ERROR: AccountError.NAME_LENGTH}
	var clean := trim_name(name)
	if clean.length() < min_name or clean.length() > max_name:
		return {KEY_ERROR: AccountError.NAME_LENGTH}
	if not is_valid_name_text(clean) or (name_filter.is_valid() and not name_filter.call(clean)):
		return {KEY_ERROR: AccountError.NAME_CHARACTERS}
	if password.length() < min_password:
		return {KEY_ERROR: AccountError.PASSWORD_SHORT}
	if _over(password.length(), _password_cap()):
		return {KEY_ERROR: AccountError.PASSWORD_LONG}
	if _id_of_name(clean) != '':
		return {KEY_ERROR: AccountError.NAME_TAKEN}
	var account_id := LFUuid.token(_ACCOUNT_ID_LENGTH)
	_accounts()[account_id] = _new_account(clean, password)
	_ids_by_key[name_key(clean)] = account_id
	var session := _session(account_id)
	if session.has(KEY_ERROR):
		_accounts().erase(account_id)
		_ids_by_key.erase(name_key(clean))
	return session


## Opens a new session for an existing account: `{account_id, name, token}`, or
## `{error: BAD_CREDENTIALS}` whether the name or the password was wrong, or
## `{error: STORE_UNAVAILABLE}`. A name longer than `max_name_input` or a password longer
## than `max_password` answers `BAD_CREDENTIALS` at once, without hashing. The password is checked with the rounds the account's hash
## was made with; when those differ from `rounds`, the password is re-hashed with `rounds`
## and a new salt, which costs a second hash. An account whose stored rounds lie outside
## 1..`MAX_STORED_ROUNDS` (a damaged file) is not hashed: it answers `BAD_CREDENTIALS`
## with a pushed error. Saves the file.
func sign_in(name: String, password: String) -> Dictionary:
	if not is_writable():
		return {KEY_ERROR: AccountError.STORE_UNAVAILABLE}
	_prune_once()
	if _over(name.length(), max_name_input) or _over(password.length(), _password_cap()):
		return {KEY_ERROR: AccountError.BAD_CREDENTIALS}
	var account_id := _id_of_name(name)
	var account: Dictionary = _accounts().get(account_id, {})
	if account.is_empty():
		# The work of a real check on an account hashed with `rounds`, so timing does not
		# set unknown names apart from those.
		LFPasswordHash.verify(password, _DUMMY_SALT, _hash_rounds(), '')
		return {KEY_ERROR: AccountError.BAD_CREDENTIALS}
	var stored_rounds := _rounds_of(account)
	if stored_rounds < 1 or stored_rounds > MAX_STORED_ROUNDS:
		_log.error('account %s stores rounds %s, outside 1..%d; its sign-in is refused until the file is fixed' % [account_id, str(account.get(_FIELD_ROUNDS)).left(_ROUNDS_SHOWN), MAX_STORED_ROUNDS])
		LFPasswordHash.verify(password, _DUMMY_SALT, _hash_rounds(), '')
		return {KEY_ERROR: AccountError.BAD_CREDENTIALS}
	if not LFPasswordHash.verify(password, str(account.get(_FIELD_SALT, '')), stored_rounds, str(account.get(_FIELD_HASH, ''))):
		return {KEY_ERROR: AccountError.BAD_CREDENTIALS}
	var before := account.duplicate()
	var new_rounds := _hash_rounds()
	if stored_rounds != new_rounds:
		var salt := LFUuid.token(_SALT_LENGTH)
		account[_FIELD_SALT] = salt
		account[_FIELD_HASH] = LFPasswordHash.compute(password, salt, new_rounds)
	account[_FIELD_ROUNDS] = new_rounds
	var session := _session(account_id)
	if session.has(KEY_ERROR):
		_accounts()[account_id] = before
	return session


## Returns `{account_id, name}` for a live session token, or `{}` for an empty, unknown or expired
## one (an expired one is dropped and the file saved; with an unusable clock every token
## gives `{}` and the file is left alone).
func resume(token: String) -> Dictionary:
	_prune_once()
	if token == '':
		return {}
	var token_hash := token.sha256_text()
	var session: Dictionary = _tokens().get(token_hash, {})
	if session.is_empty():
		return {}
	if !_clock_usable():
		# Fails closed, but the session is not the user's to lose: nothing is dropped or saved.
		return {}
	if _expired(session):
		_tokens().erase(token_hash)
		_save()
		return {}
	var account: Variant = _accounts().get(session.get(_FIELD_ID), {})
	if not account is Dictionary or not account.get(_FIELD_NAME) is String:
		return {}
	return {KEY_ACCOUNT_ID: session[_FIELD_ID], KEY_NAME: account[_FIELD_NAME]}


## Ends the session `token` opens. Returns `true` when there was one and the file was
## saved without it. An empty or unknown token returns `false` and changes nothing; so does
## a sign-out that cannot be saved (the session stays live, as the file still holds it).
func sign_out(token: String) -> bool:
	var token_hash := token.sha256_text()
	var session: Variant = _tokens().get(token_hash)
	if session == null:
		return false
	_tokens().erase(token_hash)
	if _save():
		return true
	_tokens()[token_hash] = session
	_prune()
	return false


## Returns how many accounts exist.
func count() -> int:
	return _accounts().size()


func _load() -> void:
	_data = {_FILE_ACCOUNTS: {}, _FILE_TOKENS: {}}
	var read := LFFile.read_text(path)
	if read.error == ERR_FILE_NOT_FOUND or (read.error == OK and read.text.strip_edges() == '' and LFFile.is_blank(path)):
		load_state = LoadState.NEW
		return
	if read.error != OK:
		load_state = LoadState.REFUSED
		_log.error('%s exists but could not be read (err=%s); it will not be overwritten, and accounts are unavailable' % [path, read.error])
		return
	var parsed: Variant = LFJson.parse_object(read.text)
	if parsed != null and _has_expected_shape(parsed):
		load_state = LoadState.LOADED
		var loaded: Dictionary = parsed
		_data[_FILE_ACCOUNTS] = loaded.get(_FILE_ACCOUNTS, {})
		_data[_FILE_TOKENS] = loaded.get(_FILE_TOKENS, {})
		_index_names()
		return
	set_aside_path = LFFile.move_aside(path, _CORRUPT_TAG)
	if set_aside_path == '':
		load_state = LoadState.REFUSED
		_log.error('%s is not an accounts file and could not be moved aside; it will not be overwritten, and accounts are unavailable' % path)
		return
	load_state = LoadState.SET_ASIDE
	_log.warning('%s is not an accounts file; moved it to %s and started with no accounts' % [path, set_aside_path])



## A JSON object whose `accounts` and `tokens`, when present, are objects.
static func _has_expected_shape(parsed: Dictionary) -> bool:
	for key: String in [_FILE_ACCOUNTS, _FILE_TOKENS]:
		if parsed.has(key) and not parsed[key] is Dictionary:
			return false
	return true


## The fields of an account holding `password` hashed with `rounds` and a new salt.
func _new_account(clean_name: String, password: String) -> Dictionary:
	var salt := LFUuid.token(_SALT_LENGTH)
	var used_rounds := _hash_rounds()
	return {
		_FIELD_NAME: clean_name,
		_FIELD_KEY: name_key(clean_name),
		_FIELD_SALT: salt,
		_FIELD_HASH: LFPasswordHash.compute(password, salt, used_rounds),
		_FIELD_ROUNDS: used_rounds,
	}


## Whether `length` exceeds `cap`; a `cap` of 0 or less is no cap.
static func _over(length: int, cap: int) -> bool:
	return cap > 0 and length > cap


## `max_password` raised to `min_password` when below it; 0 or less stays "no cap".
func _password_cap() -> int:
	return max_password if max_password <= 0 else maxi(max_password, min_password)


## `rounds` limited to what sign-in accepts back (1..MAX_STORED_ROUNDS), so a value set
## outside it cannot write accounts that no one can sign in to.
func _hash_rounds() -> int:
	return clampi(rounds, 1, MAX_STORED_ROUNDS)


## The rounds an account's hash was made with: its stored count, or legacy_rounds when it
## has none (or a hand-edited non-number). A stored number that is not finite or lies
## outside 1..MAX_STORED_ROUNDS gives 0, which sign_in refuses.
func _rounds_of(account: Dictionary) -> int:
	var stored: Variant = account.get(_FIELD_ROUNDS)
	if stored is int:
		return stored if stored >= 1 and stored <= MAX_STORED_ROUNDS else 0
	if stored is float:
		var value: float = stored
		return int(value) if value >= 1.0 and value <= MAX_STORED_ROUNDS else 0
	return legacy_rounds


## Opens a session and saves; on a failed save the session is dropped again and
## `{error: STORE_UNAVAILABLE}` returned.
func _session(account_id: String) -> Dictionary:
	if !_clock_usable():
		return {KEY_ERROR: AccountError.STORE_UNAVAILABLE}
	var token := LFUuid.token(_SESSION_TOKEN_LENGTH)
	var token_hash := token.sha256_text()
	var dropped := _make_room_for_session(account_id)
	_tokens()[token_hash] = {_FIELD_ID: account_id, _FIELD_EXPIRES: float(clock_unix_seconds.call()) + token_ttl_seconds}
	if not _save():
		_tokens().erase(token_hash)
		_tokens().merge(dropped)
		_prune()
		return {KEY_ERROR: AccountError.STORE_UNAVAILABLE}
	return {KEY_ACCOUNT_ID: account_id, KEY_NAME: _accounts()[account_id][_FIELD_NAME], KEY_TOKEN: token}


## Ends the account's sessions that expire soonest until one more fits under
## max_sessions; returns the ended ones (token hash -> session), to restore on failure.
func _make_room_for_session(account_id: String) -> Dictionary:
	var dropped := {}
	var owned: Array = _tokens_by_account.get(account_id, []).filter(func(token_hash: String) -> bool:
		return _tokens().has(token_hash))
	var limit := maxi(max_sessions, 1)
	if owned.size() < limit:
		return dropped
	owned.sort_custom(func(a: String, b: String) -> bool:
		return float(_tokens()[a][_FIELD_EXPIRES]) < float(_tokens()[b][_FIELD_EXPIRES]))
	for i in owned.size() - limit + 1:
		dropped[owned[i]] = _tokens()[owned[i]]
		_tokens().erase(owned[i])
	return dropped


func _id_of_name(name: String) -> String:
	return _ids_by_key.get(name_key(name), '')


## Builds the name index from each account's stored `key`, passed through `name_key` again
## so a key stored before that folding finds its account. An entry without a String `key`
## or `name` (a hand-edited file) is skipped; when two accounts share a key, the first in
## the file wins.
func _index_names() -> void:
	_ids_by_key.clear()
	for account_id: Variant in _accounts():
		var account: Variant = _accounts()[account_id]
		if account is Dictionary:
			var stored_key: Variant = account.get(_FIELD_KEY)
			if stored_key is String and account.get(_FIELD_NAME) is String and not _ids_by_key.has(name_key(stored_key)):
				_ids_by_key[name_key(stored_key)] = account_id


## Whether `clock_unix_seconds` can be called; reports once when it cannot (its object was freed).
func _clock_usable() -> bool:
	if clock_unix_seconds.is_valid():
		return true
	if !_clock_error_reported:
		_clock_error_reported = true
		_log.error('clock_unix_seconds can no longer be called; sessions count as expired and none is opened')
	return false


## A session without a numeric `expires` (a hand-edited file) counts as expired, and so
## does every session when `clock_unix_seconds` can no longer be called.
func _expired(session: Dictionary) -> bool:
	if !_clock_usable():
		return true
	var expires: Variant = session.get(_FIELD_EXPIRES)
	if not (expires is float or expires is int):
		return true
	return float(expires) < float(clock_unix_seconds.call())


## The stored accounts (account id -> account); always the live dictionary.
func _accounts() -> Dictionary:
	return _data[_FILE_ACCOUNTS]


## The stored sessions (token hash -> session); always the live dictionary.
func _tokens() -> Dictionary:
	return _data[_FILE_TOKENS]


## Drops expired tokens once, on the first use after loading — not in the constructor, so
## a `clock_unix_seconds` set right after construction is the one that judges them.
func _prune_once() -> void:
	if not _pruned:
		_pruned = true
		_prune()


## Drops expired and malformed sessions and rebuilds the sessions-per-account index.
## While the clock cannot be called nothing can be judged expired, so only malformed
## sessions are dropped and the rest stay in the file for a working clock to judge.
func _prune() -> void:
	_tokens_by_account.clear()
	var judge := _clock_usable()
	for token_hash: Variant in _tokens().keys():
		var session: Variant = _tokens()[token_hash]
		if not session is Dictionary or (judge and _expired(session)):
			_tokens().erase(token_hash)
			continue
		var owner: Variant = session.get(_FIELD_ID)
		if not _tokens_by_account.has(owner):
			_tokens_by_account[owner] = []
		_tokens_by_account[owner].append(token_hash)


## Prunes and writes the whole file. Returns whether it was written; a REFUSED store
## never writes.
func _save() -> bool:
	if not is_writable():
		return false
	_pruned = true
	_prune()
	return LFFile.save_json(path, _data)
