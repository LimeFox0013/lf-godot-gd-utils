# lf_accounts

> Player accounts for your own game server: sign up and sign in with a name and password, and stay signed in with a token, kept in one JSON file without storing passwords.

| | |
|---|---|
| **Files** | `lf_password_hash.gd`, `lf_account_store.gd` |
| **Tests** | `tests/test_lf_password_hash.gd`, `tests/test_lf_account_store.gd` (in the repository; the release zip leaves tests out) |
| **Depends on** | `LFFile`, `LFJson`, `LFLogger`, `LFUuid` |

**Classes** ([how LF classes work](../../../README.md#how-lf-classes-work)):

| Class | How you use it |
|---|---|
| `LFAccountStore` | Object: create it with `.new()` |
| `LFPasswordHash` | Static: call it on the class name |

## When to use it

Use `LFAccountStore` when your game's own server needs player accounts: a name and a
password to sign up and sign in, and a "remember me" token so the player is not asked
again on the next launch. It runs where the file lives (a dedicated server, or a
host's machine), stores no passwords, and gives the same answer for a wrong name and a
wrong password. It suits a small community server: up to a few thousand accounts (see
Notes for the measured costs). Use `LFPasswordHash` alone if you keep accounts somewhere
else and only need to hash and check passwords. For a single-player save file you do not
need accounts at all (see `LFFile`); for many thousands of players, accounts across
several servers, or anything where a stolen password file would be serious, use a hosted
service or a real database with a memory-hard password hash (Argon2, scrypt).

## Step by step

**Before you start:** this class only keeps the account file and checks passwords. It does
no networking: your server code receives the name and password and calls it, so send
passwords only over an encrypted connection: `wss://` (an `LFSocketServer` listening with
`TLSOptions`, or a TLS reverse proxy in front of it) or `https://`. It is meant for a
server or a host's machine, not for something a player can open and edit. Every call runs
on the calling thread: a sign-up or sign-in costs one or two password hashes (about 25 ms
each with the default rounds on an Apple M2 Max; more on a small cloud server) plus a
rewrite of the whole file.

1. In the Godot editor choose *Scene → New Scene*. In the Scene dock click **Other Node**,
   pick **Node**, and press *Create*. Save it (*Ctrl+S*, Cmd+S on macOS) as `accounts_demo.tscn`.
2. Right-click the Node in the Scene dock and choose *Attach Script*, then press *Create*.
3. Replace everything in the script with this:

```gdscript
extends Node


func _ready() -> void:
	# The accounts live in this file. "user://" is a folder Godot keeps for your game.
	var accounts := LFAccountStore.new("user://my_accounts.json")

	# Create an account. The result is a Dictionary: it holds "error" on failure,
	# or "name" and "token" on success.
	var made := accounts.sign_up("Ada", "correct horse")
	if made.has("error"):
		# find_key turns the error number into its name, e.g. NAME_TAKEN.
		print("Sign-up failed: ", LFAccountStore.AccountError.find_key(made["error"]))
	else:
		print("Created account: ", made["name"])

	# Sign in later. Names ignore upper/lower case. The token is the "remember me" key.
	var session := accounts.sign_in("ada", "correct horse")
	print("Signed in: ", session.has("token"))

	# A wrong password and an unknown name give the same answer on purpose.
	print("Wrong password refused: ", accounts.sign_in("Ada", "wrong").has("error"))

	# Next launch the player sends the token instead of the password.
	print("Token still good: ", accounts.resume(session["token"])["name"])

	# Signing out ends that token.
	accounts.sign_out(session["token"])
	print("Token after sign-out: ", accounts.resume(session["token"]).is_empty())
```

4. Press *F6* (Run Current Scene). In the **Output** panel at the bottom you should see
   `Created account: Ada`, `Signed in: true`, `Wrong password refused: true`,
   `Token still good: Ada` and `Token after sign-out: true`. Hashing a password is slow on
   purpose (a few hundredths of a second each).
5. Run it a second time. The file remembers the account, so the first line becomes
   `Sign-up failed: NAME_TAKEN` and the rest still work. To start fresh, choose
   *Project → Open User Data Folder* and delete `my_accounts.json`.
6. Make it yours: change the file name; pass options as a second argument to change the
   limits, for example `{"min_password": 12, "token_ttl_seconds": 7 * 86400.0}` (password at
   least 12 characters; tokens live 7 days, counted in seconds). Check
   `accounts.load_state` after `.new()`: `REFUSED` means the file exists but could not be
   used, and every sign-up and sign-in answers `STORE_UNAVAILABLE` until you fix it.

## API

Everything the class offers; you only need the rows used above to get started.

### LFPasswordHash (static)

| Member | Signature | Description |
|---|---|---|
| `compute` | `static compute(password: String, salt: String, rounds: int) -> String` | HMAC-SHA256 iterated `rounds` times (at least 1): key = salt's UTF-8 bytes, first message = password's UTF-8 bytes, each digest the next message. Lowercase hex, 64 characters. |
| `verify` | `static verify(password: String, salt: String, rounds: int, expected_hex: String) -> bool` | `compute(...)` compared to `expected_hex` with `equals_full_scan` (compares every byte instead of stopping at the first difference; computing the hash dominates anyway). |
| `equals_full_scan` | `static equals_full_scan(a: String, b: String) -> bool` | Equality that looks at every byte of the longer string instead of stopping at the first difference. The length still shows in the time; GDScript gives no hard timing guarantee. |

### LFAccountStore

| Member | Signature | Description |
|---|---|---|
| `_init` | `LFAccountStore.new(file_path: String, options: Dictionary = {}, initial_clock_unix_seconds := Callable())` | Loads `file_path` and sets `load_state`: a missing, empty or whitespace-only file starts empty (`NEW`); a file that is not a JSON object (a file of control bytes such as zero bytes counts as not one) with object `accounts`/`tokens` is moved to `<file>.corrupt-<unix time>` first (`SET_ASIDE`, pushed warning); a file that can't be read, or can't be moved aside, is left untouched and the store refuses every change (`REFUSED`, pushed error). `options` overrides any of `DEFAULTS`, and may set `name_filter`; any other key is ignored and reported as an error naming it. `initial_clock_unix_seconds` sets `clock_unix_seconds` (without it: `Time.get_unix_time_from_system`). |
| `DEFAULTS` | `const DEFAULTS: Dictionary` | `{min_name: DEFAULT_MIN_NAME, max_name: DEFAULT_MAX_NAME, min_password: DEFAULT_MIN_PASSWORD, max_password: DEFAULT_MAX_PASSWORD, max_name_input: DEFAULT_MAX_NAME_INPUT, rounds: DEFAULT_ROUNDS, legacy_rounds: LEGACY_ROUNDS, token_ttl_seconds: DEFAULT_TOKEN_TTL_SECONDS, max_sessions: DEFAULT_MAX_SESSIONS}`. |
| `DEFAULT_MIN_NAME` | `const DEFAULT_MIN_NAME: int` | `3`. |
| `DEFAULT_MAX_NAME` | `const DEFAULT_MAX_NAME: int` | `24`. |
| `DEFAULT_MIN_PASSWORD` | `const DEFAULT_MIN_PASSWORD: int` | `8`. |
| `DEFAULT_MAX_PASSWORD` | `const DEFAULT_MAX_PASSWORD: int` | `1024`. |
| `DEFAULT_MAX_NAME_INPUT` | `const DEFAULT_MAX_NAME_INPUT: int` | `256`. |
| `DEFAULT_ROUNDS` | `const DEFAULT_ROUNDS: int` | `20000` (see Notes for what that buys). |
| `LEGACY_ROUNDS` | `const LEGACY_ROUNDS: int` | `20000`, the default `legacy_rounds`: the rounds this class hashed with before it stored a `rounds` field per account. |
| `DEFAULT_TOKEN_TTL_SECONDS` | `const DEFAULT_TOKEN_TTL_SECONDS: float` | `30 * 86400.0` (30 days). |
| `DEFAULT_MAX_SESSIONS` | `const DEFAULT_MAX_SESSIONS: int` | `10`. |
| `KEY_ACCOUNT_ID` | `const KEY_ACCOUNT_ID: String` | `'account_id'`, the result key of the account id. |
| `KEY_NAME` | `const KEY_NAME: String` | `'name'`, the result key of the account name. |
| `KEY_TOKEN` | `const KEY_TOKEN: String` | `'token'`, the result key of the session token. |
| `KEY_ERROR` | `const KEY_ERROR: String` | `'error'`, the result key of an `AccountError`. |
| `AccountError` | `enum { NAME_LENGTH, PASSWORD_SHORT, NAME_TAKEN, BAD_CREDENTIALS, NAME_CHARACTERS, STORE_UNAVAILABLE, PASSWORD_LONG }` | Why a call failed. `NAME_LENGTH`: the trimmed name is outside `min_name`..`max_name`, or the name as typed is longer than `max_name_input`. `PASSWORD_LONG`: the password is longer than `max_password` (`sign_up` only; `sign_in` answers `BAD_CREDENTIALS`). `NAME_CHARACTERS`: the name holds a control or invisible character or no letter or digit (see `is_valid_name_text`), or `name_filter` refused it. `NAME_TAKEN`: another account has the same `name_key`. `STORE_UNAVAILABLE`: the store is `REFUSED`, or the change could not be saved (nothing was kept). |
| `LoadState` | `enum { NEW, LOADED, SET_ASIDE, REFUSED }` | What `.new()` found at the path (see `_init`). |
| `load_state` | `var load_state: LoadState` | Set by `.new()`. |
| `set_aside_path` | `var set_aside_path: String` | Where a malformed file was moved (`SET_ASIDE`); `""` otherwise. |
| `is_writable` | `is_writable() -> bool` | `load_state != REFUSED`. |
| `is_valid_name_text` | `static is_valid_name_text(name: String) -> bool` | `false` when `name` holds a C0/C1 control character (U+0000–U+001F, U+007F–U+009F); a code point Unicode lists as Default_Ignorable_Code_Point (U+00AD, U+034F, U+061C, U+115F–U+1160, U+17B4–U+17B5, U+180B–U+180F, U+200B–U+200F, U+202A–U+202E, U+2060–U+206F, U+3164, U+FE00–U+FE0F, U+FEFF, U+FFA0, U+FFF0–U+FFF8, U+1BCA0–U+1BCA3, U+1D173–U+1D17A, U+E0000–U+E0FFF); the line or paragraph separator U+2028–U+2029; the blank Braille pattern U+2800; U+FFF9–U+FFFB; a lone surrogate or a value above U+10FFFF. Also `false` when it shows no letter (a Unicode identifier start other than `_`, as `String.is_valid_unicode_identifier` judges it) and no ASCII digit `0`–`9` (fullwidth forms count as ASCII): `---`, `___` or only combining marks are refused. Digits of other scripts alone (`٣٣٣`) count as no letter. See Notes for what is not detected. |
| `trim_name` | `static trim_name(name: String) -> String` | `name` without Unicode whitespace at either end (ASCII whitespace, U+0085, U+00A0, U+1680, U+2000–U+200A, U+2028–U+2029, U+202F, U+205F, U+3000); `String.strip_edges` trims ASCII only. `sign_up` stores the name trimmed this way. |
| `name_key` | `static name_key(name: String) -> String` | The key two accounts may not share: `trim_name(name)`, each run of whitespace inside made one space, fullwidth ASCII (U+FF01–U+FF5E) made ASCII, then lower-cased. `"Admin"`, `" admin\u00A0"` and `"ａｄｍｉｎ"` share `"admin"`. |
| `name_filter` | `var name_filter: Callable` | Extra check a new name must pass after the built-in ones: called with the trimmed name, returns `true` to accept. A refused name fails `sign_up` with `NAME_CHARACTERS`. Empty by default; set it here or with the `name_filter` option (not part of `DEFAULTS`). See Usage for an ASCII-only filter. |
| `MAX_STORED_ROUNDS` | `const MAX_STORED_ROUNDS: int` | `5000000`. An account whose stored `rounds` is not a number from 1 to this (a damaged or hand-edited file) is not hashed at sign-in: it answers `BAD_CREDENTIALS` with a pushed error naming the account. |
| `path` | `var path: String` | The file saves go to. Changing it does not reload. |
| `min_name` | `var min_name: int` | Shortest allowed name in characters (code points), after `trim_name`. |
| `max_name` | `var max_name: int` | Longest allowed name in characters (code points), after `trim_name`. |
| `min_password` | `var min_password: int` | Shortest allowed password. |
| `max_password` | `var max_password: int` | Longest allowed password in characters; 0 or less means no cap; below `min_password` it is used as `min_password`. Lowering it locks out accounts whose password is longer (`sign_in` refuses it unchecked). |
| `max_name_input` | `var max_name_input: int` | Longest allowed name as typed, before `trim_name`, in characters; 0 or less means no cap. |
| `rounds` | `var rounds: int` | Rounds for new hashes (a value outside 1..`MAX_STORED_ROUNDS` is used as the nearest limit). Each account stores its own, so changing this locks out no account that stores them: such an account is checked with its stored rounds and re-hashed with `rounds` (new salt) on its next successful sign-in. An account without stored rounds is checked with `legacy_rounds`. |
| `legacy_rounds` | `var legacy_rounds: int` | Rounds an account without a stored `rounds` field is checked with (option `legacy_rounds`, default `LEGACY_ROUNDS`). It must equal the rounds the old file's hashes were made with; files this class wrote before it stored rounds used `LEGACY_ROUNDS`. |
| `token_ttl_seconds` | `var token_ttl_seconds: float` | Seconds a new session token lives. A NaN is rejected: reported as an error, the value is kept. |
| `max_sessions` | `var max_sessions: int` | Most live sessions per account (at least 1); a new one ends the session that expires soonest. |
| `clock_unix_seconds` | `var clock_unix_seconds: Callable` | Unix seconds now, for token expiry (written to the file); `Time.get_unix_time_from_system` by default. Replaceable. |
| `sign_up` | `sign_up(name: String, password: String) -> Dictionary` | `{account_id, name, token}` (the name after `trim_name`, otherwise as typed), or `{error}` (`NAME_LENGTH` (also for a name as typed over `max_name_input`, checked before trimming), `NAME_CHARACTERS`, `PASSWORD_SHORT`, `PASSWORD_LONG`, `NAME_TAKEN`, `STORE_UNAVAILABLE`). Saves. |
| `sign_in` | `sign_in(name: String, password: String) -> Dictionary` | `{account_id, name, token}`, or `{error: BAD_CREDENTIALS}` for either wrong half, or `{error: STORE_UNAVAILABLE}`. A name over `max_name_input` or a password over `max_password` answers `BAD_CREDENTIALS` at once, without hashing. The name is matched by `name_key`. Re-hashes when the account's stored rounds differ from `rounds`. An account whose stored rounds are outside 1..`MAX_STORED_ROUNDS` answers `BAD_CREDENTIALS` without hashing, with a pushed error. Saves. |
| `resume` | `resume(token: String) -> Dictionary` | `{account_id, name}` for a live token, `{}` otherwise (an expired one is dropped). |
| `sign_out` | `sign_out(token: String) -> bool` | Ends that session and saves; `true` when there was one and the save succeeded. `false` for an empty or unknown token, and for a save that failed: the session then stays live (the file still holds it). |
| `count` | `count() -> int` | Number of accounts. |

## Usage

Each `sign_up`/`sign_in` costs one or two password hashes on the calling thread (about
25 ms each by default on an Apple M2 Max), so a server that answers every login request at
once can be stalled by someone sending thousands of them. This server refuses an address
that keeps failing (with `LFStrikeGuard`, keyed by `LFStrikeGuard.address_key` so one IPv6
user counts once), and answers at most one sign-in or sign-up per address every half
second (`last_try`):

```gdscript
# account_server.gd: on the server, a Node that answers sign-up and sign-in requests.
extends Node

var accounts := LFAccountStore.new("user://accounts.json")
# 5 failures within 60 s lock that address out for 300 s.
var guard := LFStrikeGuard.new(5, 60.0, 300.0)
# Address key -> when it last asked to sign in or up (ms).
var last_try := {}


func _ready() -> void:
	if accounts.load_state == LFAccountStore.LoadState.REFUSED:
		push_error("accounts.json can't be read; fix it before players sign in")


# `address` is where the request came from, e.g. LFSocketServer.peer_address(peer_id).
# Behind a reverse proxy that is the proxy's address: use the client address it passes
# on instead, or every player shares one lockout.
# Each function returns the text to show the player, and the token to keep on success.
func handle_sign_up(address: String, player_name: String, password: String) -> Dictionary:
	var key := LFStrikeGuard.address_key(address)
	if not _may_try(key):
		return {"message": "Too many attempts. Try again later."}
	var result := accounts.sign_up(player_name, password)
	if result.has("error"):
		return {"message": _error_text(result["error"])}
	return {"message": "Welcome, %s!" % result["name"], "token": result["token"]}


func handle_sign_in(address: String, player_name: String, password: String) -> Dictionary:
	var key := LFStrikeGuard.address_key(address)
	if not _may_try(key):
		return {"message": "Too many attempts. Try again later."}
	var result := accounts.sign_in(player_name, password)
	if result.has("error"):
		if result["error"] == LFAccountStore.AccountError.BAD_CREDENTIALS:
			guard.strike(key)
		return {"message": _error_text(result["error"])}
	return {"message": "Welcome back, %s!" % result["name"], "token": result["token"]}


# Next launch: the client sends its saved token instead of the password. One SHA-256, not
# thousands of hash rounds, so it costs far less than sign_in.
func handle_resume(token: String) -> String:
	var session := accounts.resume(token)
	if session.is_empty():
		return "Please sign in again."
	return "Welcome back, %s!" % session["name"]


# Refuses a blocked address, and one that asked less than 500 ms ago.
func _may_try(key: String) -> bool:
	if guard.is_blocked(key):
		return false
	var now := Time.get_ticks_msec()
	if now - int(last_try.get(key, -1000)) < 500:
		return false
	last_try[key] = now
	return true


func _error_text(error: LFAccountStore.AccountError) -> String:
	match error:
		LFAccountStore.AccountError.NAME_LENGTH:
			return "Names are %d to %d characters." % [accounts.min_name, accounts.max_name]
		LFAccountStore.AccountError.NAME_CHARACTERS:
			return "Names need a letter or digit and can't hold control or invisible characters."
		LFAccountStore.AccountError.PASSWORD_SHORT:
			return "Use at least %d characters." % accounts.min_password
		LFAccountStore.AccountError.NAME_TAKEN:
			return "That name is taken."
		LFAccountStore.AccountError.STORE_UNAVAILABLE:
			return "Accounts are unavailable right now."
	return "Wrong name or password."
```

The per-address limits bound what one address costs you; many addresses at once (a
botnet) can still keep the server busy, at 64 logins in one frame about 1.6 s of hashing.
For that, cap sign-ins per frame across all addresses in your own code, or put a rate
limiting proxy in front. Call `guard.prune()` and clear old `last_try` entries every few
seconds on a long-running server.

Hashing a password on its own. These lines go inside a function of any script:

```gdscript
var salt := LFUuid.token(16)
var stored := LFPasswordHash.compute("hunter22", salt, 20000)   # store the rounds with it
print(LFPasswordHash.verify("hunter22", salt, 20000, stored))   # true
```

## Notes

- **Input size.** `max_name_input` (default 256, the name as typed) and `max_password` (default 1024) bound the work of `sign_up` and `sign_in`, which is linear in the input: both refuse an over-cap input before hashing (`sign_in` with `BAD_CREDENTIALS`). Setting either to 0 or less removes that cap; then the cost is about 1.2 s per million characters of name in `sign_in` (a password about 8 ms per million; measured on one Mac, Godot 4.7), so bound the size of what you pass in (behind `LFSocketServer`, `inbound_buffer_size` does). Lowering `max_password` locks out existing accounts whose password is longer than the new cap, since `sign_in` refuses it without checking.

- **Stored format.** The file is `{accounts: {id: {name, key, salt, hash, rounds}}, tokens: {sha256(token): {id, expires}}}` — `key` is the account's `name_key` (lower-cased, trimmed, whitespace runs and fullwidth forms folded; a key stored before that folding is folded again when loaded, so it still finds its account), `rounds` the rounds that account's hash was made with, `expires` is in `clock_unix_seconds` seconds. An account without `rounds` (files written before it was stored) is checked with `legacy_rounds` (default `LEGACY_ROUNDS`, 20000) and gets `rounds` on its next sign-in. Passwords and raw tokens are never written. Ids and salts are `LFUuid.token(16)`, session tokens `LFUuid.token(32)`.
- **How strong the hash is.** `LFPasswordHash` repeats an HMAC-SHA256 keyed by the salt `rounds` times; it is not PBKDF2, but each round costs about what a PBKDF2-HMAC-SHA256 iteration costs. OWASP's Password Storage Cheat Sheet recommends 600,000 PBKDF2-HMAC-SHA256 iterations (and prefers Argon2id or scrypt). The default 20,000 is **30 times fewer**, and an attacker with a stolen file runs SHA-256 on GPUs far faster than this GDScript loop: treat a stolen account file as crackable for weak or common passwords. Measured on an Apple M2 Max (Godot 4.7): 20,000 rounds take about 25 ms, so OWASP's count would take about 0.75 s per sign-in, on the main thread. The default is a compromise for a server that hashes on its main thread; raise `rounds` if your server can afford it (accounts re-hash on their next sign-in) and keep the file private. A per-account salt still means equal passwords hash differently and one guess cannot be tried against every account at once.
- Godot's own HMAC function refuses an empty key or message; those cases are computed by hand to the same standard, so an empty salt or password still hashes.
- **Timing.** An unknown name costs one hash with `rounds`; a wrong password costs one hash with that account's stored rounds (or `legacy_rounds`). So how long the answer takes does not set unknown names apart from accounts hashed with the current `rounds`. An account still on other rounds answers in a different time, which can tell a guesser the name exists, until its next successful sign-in re-hashes it (that sign-in costs a second hash).
- **A file the store can't use is never overwritten.** Content that is not a JSON object (a file of control bytes such as zero bytes included), or whose `accounts` or `tokens` is not an object, is moved to `<file>.corrupt-<unix time>` before the store starts empty (`load_state` `SET_ASIDE`, `set_aside_path`). A file that exists but can't be read, or can't be moved aside, is left as it is: `load_state` is `REFUSED` and every `sign_up`/`sign_in` returns `STORE_UNAVAILABLE`. A save that fails (disk full, permissions) in `sign_up` or `sign_in` keeps nothing of that call and returns `STORE_UNAVAILABLE`; in `sign_out` it returns `false` and the session stays live. Individual entries with the wrong types (an account whose `key` or `name` is not a String, a session whose `expires` is not a number) are skipped without an engine error; such a session counts as expired and is dropped at the next save. An account whose `rounds` is a number outside 1..`MAX_STORED_ROUNDS` is refused at sign-in (see `MAX_STORED_ROUNDS`), so a damaged count cannot make one sign-in hash for hours.
- Expired tokens are dropped on the first call after loading and on every save. (`clock_unix_seconds` is the "seconds now" function used to judge expiry; set it right after `.new()` if you replace it.) Each account keeps at most `max_sessions` live sessions; a new one ends the one that expires soonest.
- **A freed clock fails closed.** If `clock_unix_seconds` can no longer be called (the object behind it was freed), every session counts as expired in memory (`resume` returns `{}`), but none is dropped from the file: pruning and `resume` leave the stored sessions alone, so a save made meanwhile keeps them for a working clock, `sign_up` and `sign_in` return `STORE_UNAVAILABLE` instead of opening a session, and an error is reported once.
- Names are looked up through an in-memory index, not by scanning every account.
- **What makes two names the same, and what does not.** Names are compared by `name_key`: case (Godot's `to_lower`), Unicode whitespace at the ends, how many whitespace characters separate words, and fullwidth ASCII (`ａｄｍｉｎ`) are ignored. Invisible characters and names with no letter or digit are refused (`is_valid_name_text`). Godot has no Unicode normalization or confusables data, so these are **not** detected: look-alike letters from other scripts (Cyrillic `аdmin`, Greek `Α`), Turkish dotless `ı` or dotted `İ`, a letter written with a combining accent versus the same letter precomposed (`café` typed two ways is two accounts), and other compatibility forms (ligatures, superscripts, circled letters). To close those gaps for your game, pass a `name_filter`; the simplest strict policy is ASCII only:

  ```gdscript
  var ascii_only := func(name: String) -> bool:
  	for i in name.length():
  		if name.unicode_at(i) > 0x7E:
  			return false
  	return true
  var accounts := LFAccountStore.new("user://accounts.json", {"name_filter": ascii_only})
  ```

  Names stored before these rules (an existing file) are not re-checked; only new sign-ups are.
- Pair it with `LFStrikeGuard` (keyed by `LFStrikeGuard.address_key`) to lock out people who keep guessing passwords; see Usage.
- **Scale.** Every successful sign-up, sign-in, sign-out and expired-token drop rewrites the whole file on the calling thread. Measured on an Apple M2 Max: about 5 ms for 1,000 accounts (330 KiB), 55 ms for 10,000 (3.3 MiB), 290 ms for 50,000 (16 MiB), each with one session. It suits up to a few thousand accounts; beyond that, use a database.
- Only one `LFAccountStore` (one process) may use a file at a time: two would overwrite each other's changes.
