# LFStrikeGuard

> A lockout against guessing: someone who fails too many times in a short while is blocked for a while.

| | |
|---|---|
| **Kind** | [Object](../../../README.md#how-lf-classes-work): create it with `.new()` |
| **Files** | `lf_strike_guard.gd` |
| **Tests** | `tests/test_lf_strike_guard.gd` (in the repository; the release zip leaves tests out) |
| **Depends on** | `LFLogger` |

## When to use it

Use it to stop someone from guessing their way in: for example, after 5 wrong passwords (or room
codes, or invite keys) within a minute, that address is locked out for 5 minutes (you choose the numbers; there are no defaults). It counts
failures per key, so one player's mistakes lock out only that key (players who share
one, such as several behind one IPv4 address, share the lockout; see Notes). For "an action may
happen at most once every N ms" use `LFCooldown` or `LFThrottle` instead; this class is
about counting failures, not spacing actions.

## Step by step

It is plain bookkeeping with no network and no nodes, so you can try it in an empty scene.
In a real game the "key" is whatever identifies the guesser: an address, a peer id or an
account name.

1. In the Godot editor choose *Scene → New Scene*. In the Scene dock click **Other Node**,
   pick **Node**, and press *Create*. Save it (*Ctrl+S*, Cmd+S on macOS) as `guard_demo.tscn`.
2. Right-click the Node in the Scene dock and choose *Attach Script*, then press *Create*.
3. Replace everything in the script with this:

```gdscript
extends Node


func _ready() -> void:
	# 3 failures within 10 seconds block that player for 30 seconds.
	var guard := LFStrikeGuard.new(3, 10.0, 30.0)
	var who := "player-1"   # the key: anything that identifies the guesser

	# Pretend the player types a wrong password five times in a row.
	for attempt in 5:
		if guard.is_blocked(who):
			# Refuse before even checking the password.
			print("Attempt ", attempt + 1, ": locked out")
		else:
			# The password was wrong: record a strike. It returns true when this
			# strike was the one that locked the player out.
			var locked_now := guard.strike(who)
			print("Attempt ", attempt + 1, ": wrong password", " (now locked out)" if locked_now else "")
```

4. Press *F6* (Run Current Scene). In the **Output** panel at the bottom you should see
   `Attempt 1: wrong password`, `Attempt 2: wrong password`,
   `Attempt 3: wrong password (now locked out)`, then `Attempt 4: locked out` and
   `Attempt 5: locked out`.
5. Make it yours: change the three numbers (strikes allowed, the time they count in, and
   how long the block lasts; the last two are seconds). Use the player's address or id
   as the key. In a real login, check `is_blocked` first, and call `strike` only when
   the password was wrong. See Usage for a full server script.

## API

Everything the class offers; you only need the rows used above to get started.

| Member | Signature | Description |
|---|---|---|
| `_init` | `LFStrikeGuard.new(strikes_to_block: int, strike_window_seconds: float, block_duration_seconds: float, initial_clock_seconds := Callable())` | `strikes_to_block` strikes within `strike_window_seconds` seconds block a key for `block_duration_seconds` seconds. `initial_clock_seconds` sets `clock_seconds` and returns seconds; without it, `steady_seconds()`. Pushes an error when `block_duration_seconds` is not above zero (a block that ends at once) or `strike_window_seconds` is not above zero or is NaN while `strikes_to_block` is above 1 (strikes never add up). |
| `max_strikes` | `var max_strikes: int` | Strikes within the window that block a key (1 or less: the first strike blocks). May be changed at any time. |
| `window_seconds` | `var window_seconds: float` | Seconds a strike keeps counting. May be changed at any time. A NaN is rejected: reported as an error, the value is kept. |
| `block_seconds` | `var block_seconds: float` | Seconds a key stays blocked; affects blocks that start afterwards. |
| `clock_seconds` | `var clock_seconds: Callable` | Returns now in seconds. Replaceable (a simulated or test clock). |
| `steady_seconds` | `static steady_seconds() -> float` | The default clock: `Time.get_ticks_msec() / 1000.0`. |
| `address_key` | `static address_key(address: String) -> String` | The key to strike an address under: IPv4 in dotted decimal without leading zeros (Godot accepts `01.2.3.4` and reads each part as decimal, so it is keyed as `1.2.3.4`); IPv6 as its /64 network, written as the first four groups in lower-case hex without leading zeros (none folded into `::`) plus `::/64`: `2001:db8:0:1::/64` for `2001:db8:0:1:2:3:4:5`, `fe80:0:0:0::/64` for `fe80::1`. An IPv4-mapped address (`::ffff:1.2.3.4`, `::ffff:102:304`, or written out in full) as the dotted IPv4 address (`1.2.3.4`). Brackets and a zone (`%eth0`) are dropped; anything that is not an IP address, an address with a port (`1.2.3.4:80`) included, is returned unchanged. |
| `is_blocked` | `is_blocked(key: Variant) -> bool` | Blocked now. A block that has run out is cleared here. |
| `strike` | `strike(key: Variant) -> bool` | Records a failed attempt; true when this one blocks the key (its strikes are then forgotten). Strikes while blocked are recorded again from zero; when they reach the limit again, the block restarts from that moment. |
| `forget` | `forget(key: Variant) -> void` | Forgets the key's strikes and lifts its block (an admin unblock). |
| `clear` | `clear() -> void` | Forgets every strike and lifts every block, for all keys. |
| `prune` | `prune() -> void` | Forgets keys whose strikes all aged out and blocks that ran out. |
| `tracked_count` | `tracked_count() -> int` | Keys currently held (with strikes or blocked). |

## Usage

```gdscript
# login_server.gd: a script on the Node that handles login requests.
extends Node

# 5 wrong attempts within 60 s lock that address out for 300 s.
var guard := LFStrikeGuard.new(5, 60.0, 300.0)


func _ready() -> void:
	# Forget addresses that stopped guessing, every 10 s.
	var cleanup := Timer.new()
	cleanup.wait_time = 10.0
	cleanup.autostart = true
	cleanup.timeout.connect(guard.prune)
	add_child(cleanup)


# Returns the message to send back to the player. `address` is where the request came
# from, e.g. LFSocketServer.peer_address(peer_id).
func try_login(address: String, password: String) -> String:
	# One key per IPv4 address, or per IPv6 /64 network (one user can hold all of it).
	var key := LFStrikeGuard.address_key(address)
	if guard.is_blocked(key):
		return "Too many attempts. Try again later."
	if password != "open sesame":
		guard.strike(key)
		return "Wrong password."
	return "Welcome!"
```

## Notes

- A success never clears strikes on its own, so slow guessing between successes still adds up. Call `forget(key)` only when you mean it (an admin unblock).
- `is_blocked()` clears an expired block as it reads it; after a block the key starts over with no strikes.
- Strikes older than `window_seconds` stop counting but stay in memory until the key's next strike or `prune()`. On a long-running server call `prune()` every few seconds so the guard does not grow with every key that ever failed once.
- **Keying by address.** An IPv6 user usually holds a whole /64 network (2^64 addresses) and can move to a fresh address for every guess, so key IPv6 by `address_key`, which strikes the network. A user given a larger block (a /56 or /48, common for home and business lines) can still switch between its /64 networks; this guard does not cover that. Several players behind one IPv4 address (a household, a carrier-grade NAT) share one key and so one lockout. Behind a reverse proxy or load balancer, `LFSocketServer.peer_address` is the proxy's address for everyone: one guesser would then block every player. `LFSocketServer` cannot see the player's address behind a proxy (Godot's `WebSocketPeer` does not expose the request's headers, such as `X-Forwarded-For`), so there either let the proxy do the per-address limiting, or key by something else (an account name) as well.
- A key can be any value that works as a Dictionary key (a Dictionary is Godot's key-to-value table): an address String, a peer id, an account name.
- **A freed clock fails closed.** If `clock_seconds` can no longer be called (the object behind it was freed), `is_blocked()` returns `true` for every key, `strike()` returns `true` and records nothing, `prune()` does nothing, and an error is reported once. `LFCooldown` behaves the same way.
