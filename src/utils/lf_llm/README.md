# lf_llm

> Let a language model (an AI such as Claude) pick one of the actions you define, with throttled requests that give you `null` (and, for a failed request, a logged warning) instead of a script error on every failure the client checks for: throttled, unconfigured, a malformed tool, a network error, an oversized or unusable reply.

| | |
|---|---|
| **Files** | `lf_llm_provider.gd`, `lf_anthropic_provider.gd`, `lf_open_ai_compatible_provider.gd`, `lf_llm_tool_client.gd`, `lf_llm_tool.gd` |
| **Tests** | `tests/test_lf_llm_provider.gd`, `tests/test_lf_anthropic_provider.gd`, `tests/test_lf_open_ai_compatible_provider.gd`, `tests/test_lf_llm_tool_client.gd`, `tests/test_lf_llm_tool.gd` (in the repository; the release zip leaves tests out) |
| **Depends on** | `LFHttp`, `LFCooldown`, `LFJson`, `LFLogger` |

**Classes** ([how LF classes work](../../../README.md#how-lf-classes-work)):

| Class | How you use it |
|---|---|
| `LFAnthropicProvider` | Object: create it with `.new()` |
| `LFLlmProvider` | Object: create it with `.new()` |
| `LFLlmTool` | Static: call it on the class name |
| `LFLlmToolClient` | Object: create it with `.new()` |
| `LFOpenAiCompatibleProvider` | Object: create it with `.new()` |

## When to use it

Use it to let a language model (an "LLM" such as Claude, a GPT model, or a local model in
Ollama) make decisions in your game by picking from actions you define: an AI opponent
that chooses `move(x, y)` or `wait()` each turn, or an NPC that picks a reply. You describe
each action as a tool, the model answers with one tool and its arguments, and you run it.
`LFLlmToolClient` lets game code call it as often as it likes: one request at a time, a
minimum gap between requests, a deadline, and `null` instead of an error on any failure. It does
not hold conversations or stream text; for free-form chat, call the API with `LFHttp`
directly.

A tool is provider-neutral: `{name, description, parameters}` where `parameters` is a
JSON-schema object (a standard description of an object's fields and their types). A tool
call comes back as `{name: String, input: Dictionary}`, or null.

## Step by step

**Before you start.** Each request to a hosted model such as Claude **costs money** and
needs an **API key**: a long secret password that identifies your account. You can also
use a model running on your own computer (Ollama or LM Studio, free, no key); see the end
of step 2. Needs a desktop build with internet access (or a local server).

1. **Get a key** (hosted Claude). Create an account at the Anthropic Console
   (`console.anthropic.com`), add billing, open *API Keys* and press *Create Key*. Copy the
   key at once; the page shows it only one time.

2. **Put the key in an environment variable.** An environment variable is a named note your
   computer keeps for every program it starts. LFAnthropicProvider looks for one named
   `ANTHROPIC_API_KEY`. Replace `sk-ant-your-key-here` below with your key. Godot only sees
   the variable if Godot was **started after** it was set.
   - **macOS.** Open *Terminal* and type `export ANTHROPIC_API_KEY="sk-ant-your-key-here"`
     (press Return). Then start Godot **from that same Terminal window**:
     `/Applications/Godot.app/Contents/MacOS/Godot --editor`. To make it stay for Godot
     started from the Dock or Finder, run `launchctl setenv ANTHROPIC_API_KEY "sk-ant-your-key-here"`
     once, then quit and reopen Godot (macOS forgets this at restart; run it again after
     a reboot). Adding the `export` line to the file `~/.zshrc` only affects Terminals.
   - **Windows.** Press the Start button, type `environment variables`, and open *Edit the
     environment variables for your account*. Under *User variables* press *New...*, type
     `ANTHROPIC_API_KEY` as the name and your key as the value, and press OK on every
     window. Close Godot completely and open it again. (Alternative: in *Command Prompt*,
     `setx ANTHROPIC_API_KEY "sk-ant-your-key-here"`, then reopen Godot.)
   - **Linux.** Open a terminal and type `export ANTHROPIC_API_KEY="sk-ant-your-key-here"`,
     then start Godot from that terminal (`godot --editor`). To keep it for every session,
     add that same `export` line to the end of the file `~/.profile` (or `~/.bashrc` if you
     use bash in a terminal) and log out and in again.
   - **Local model instead (no key).** Install Ollama, run `ollama pull llama3.2`, and in
     step 4 use `LFOpenAiCompatibleProvider.new("http://localhost:11434/v1", "llama3.2")`
     in place of the Anthropic line. Skip the key.

   **Never ship the key inside your game.** An exported game is just a zip of your files:
   anyone can open it and read a key written into a script, scene or setting, and then
   spend your money. The environment variable only exists on **your** computer, so a game
   you export carries no key, and your players' copies cannot call the model unless each
   player sets up their own key. If your game must use a model for everyone, send the
   request to **a server you run** and keep the key there. Also keep the key out of Git
   and out of screenshots. If a key leaks, delete it in the Console and create a new one.

3. Create the scene: *Scene → New Scene*, click **Other Node**, pick **Node**, press
   *Create*, and save it as `llm_demo.tscn`. Right-click the Node in the Scene dock,
   choose *Attach Script* and press *Create*.

4. Replace the script with this:

```gdscript
extends Node

# The actions the model may pick from. Each has a name, a description the model reads,
# the arguments it needs (names and types), and which of them are required.
var tools := [
	LFLlmTool.define("move", "Move to a cell.",
			{"x": {"type": "integer"}, "y": {"type": "integer"}}, ["x", "y"]),
	LFLlmTool.define("wait", "Do nothing this turn."),
]
# Which service to talk to: Claude, with the model name you want. It reads your key from
# the ANTHROPIC_API_KEY environment variable.
var provider := LFAnthropicProvider.new("claude-opus-5-5")
# The client sends requests: here at most one every 3000 milliseconds (3 seconds).
var client := LFLlmToolClient.new(provider, 3000)


func _ready() -> void:
	# No key found? Say what to do instead of failing.
	if not provider.is_configured():
		print(provider.setup_hint())
		return
	# "await" waits here for the model's answer while the game keeps running.
	var tool_call: Variant = await client.call_tool(
			"You control the blue team. Pick exactly one tool.",   # standing instructions
			"You are at cell 0,0 and the enemy is at cell 4,2.",   # this turn's situation
			tools)
	if tool_call == null:
		print("No usable answer (see the Output panel for a warning)")
		return
	# tool_call is {"name": ..., "input": {...}}: the chosen action and its arguments.
	print("The model chose: ", tool_call["name"], " ", tool_call["input"])
```

5. Press *F6* (Run Current Scene). Watch the **Output** panel. With the key set you should
   see a line like `The model chose: move { "x": 4.0, "y": 2.0 }` (the exact choice varies; numbers from the model arrive as decimals, and `coerce_args` below turns them into whole numbers).
   With no key set, nothing is sent and you see `Set ANTHROPIC_API_KEY to use Claude.`;
   that tells you step 2 has not taken effect yet (is Godot started after setting it?).
6. Make it yours: edit the tools to be your game's actions; change the two text arguments
   of `call_tool` (standing instructions, then the current situation); change `3000` to
   your minimum gap between requests in milliseconds. After a successful call,
   `LFLlmTool.coerce_args` turns the model's arguments into clean typed values (see Usage).

## API

Everything the class offers; you only need the rows used above to get started.

### LFLlmProvider (base)

| Member | Signature | Description |
|---|---|---|
| `display_name` | `display_name() -> String` | A short name for logs and menus. The base returns `LLM`. |
| `is_configured` | `is_configured() -> bool` | Whether the key, endpoint and model it needs are set. The base returns false. |
| `setup_hint` | `setup_hint() -> String` | What to set for `is_configured()` to become true. The base returns `''`. |
| `build_request` | `build_request(system: String, user: String, tools: Array) -> Dictionary` | `{url, headers, body}`; `body` is sent as JSON. The base returns `{}`. |
| `extract_tool_call` | `extract_tool_call(json: Variant) -> Variant` | The first tool call in a decoded response, or null (no call, a refusal, a malformed response, including fields of the wrong type). The two built-in providers do not raise on any input; an override must check each field's type before comparing it, since comparing a String with a number is a script error. |
| `KEY_NAME` | `const KEY_NAME: String` | `'name'`: a tool's name, and the name key of an extracted tool call. |
| `KEY_DESCRIPTION` | `const KEY_DESCRIPTION: String` | `'description'`: a tool's description. |
| `KEY_PARAMETERS` | `const KEY_PARAMETERS: String` | `'parameters'`: a tool's JSON-schema argument object. |
| `KEY_INPUT` | `const KEY_INPUT: String` | `'input'`: the arguments of an extracted tool call. |
| `KEY_URL` | `const KEY_URL: String` | `'url'`: the endpoint in `build_request`'s result. |
| `KEY_HEADERS` | `const KEY_HEADERS: String` | `'headers'`: the headers in `build_request`'s result. |
| `KEY_BODY` | `const KEY_BODY: String` | `'body'`: the JSON body in `build_request`'s result. |

### LFAnthropicProvider (Anthropic Messages API)

| Member | Signature | Description |
|---|---|---|
| `_init` | `LFAnthropicProvider.new(model_id: String, key_env_var := DEFAULT_API_KEY_ENV, token_limit := DEFAULT_MAX_TOKENS, effort_level := '', beta_header := '', extra_fields := {})` (`DEFAULT_MAX_TOKENS` = 4096) | Sets `model`, `api_key_env`, `max_tokens`, `effort`, `beta` and `extra_body` (deep-copied). |
| `API_URL` | `const API_URL: String` | `https://api.anthropic.com/v1/messages`. |
| `API_VERSION` | `const API_VERSION: String` | `2023-06-01`, the `anthropic-version` header. |
| `DEFAULT_API_KEY_ENV` | `const DEFAULT_API_KEY_ENV: String` | `ANTHROPIC_API_KEY`. |
| `DEFAULT_MAX_TOKENS` | `const DEFAULT_MAX_TOKENS: int` | `4096`, the default `max_tokens`. |
| `model` | `var model: String` | The model id, e.g. `claude-opus-5-5`. |
| `api_key_env` | `var api_key_env: String` | The environment variable read for the key on every call. |
| `max_tokens` | `var max_tokens: int` | The reply's `max_tokens`. |
| `effort` | `var effort: String` | `output_config.effort` (`low` … `max`); empty leaves it out. |
| `beta` | `var beta: String` | The `anthropic-beta` header; empty leaves it out. |
| `extra_body` | `var extra_body: Dictionary` | Extra body fields merged in last, overriding built ones. |
| `api_url` | `var api_url: String` (default `API_URL`) | Replaceable for a proxy or a test server. |
| `display_name` | `display_name() -> String` | `Claude`. |
| `is_configured` | `is_configured() -> bool` | The model is set and the key's environment variable is not blank (read on every call, trimmed of surrounding whitespace). |
| `setup_hint` | `setup_hint() -> String` | Names the environment variable to set. |
| `build_request` | `build_request(system: String, user: String, tools: Array) -> Dictionary` | Headers `x-api-key`, `anthropic-version` (+ `anthropic-beta`); body `model`, `max_tokens`, `system`, `tools` (with `input_schema`), `tool_choice: {type: auto}`, one user message. |
| `extract_tool_call` | `extract_tool_call(json: Variant) -> Variant` | The first `tool_use` block; `stop_reason: refusal` is null (logged). |

### LFOpenAiCompatibleProvider (Chat Completions: OpenAI, LiteLLM, Ollama, LM Studio)

| Member | Signature | Description |
|---|---|---|
| `_init` | `LFOpenAiCompatibleProvider.new(api_root := '', model_name := '', key := '', token_limit := DEFAULT_MAX_TOKENS)` (4096) | Sets `base_url`, `model`, `api_key` and `max_tokens`. |
| `DEFAULT_MAX_TOKENS` | `const DEFAULT_MAX_TOKENS: int` | `4096`, the default `max_tokens`. |
| `base_url` | `var base_url: String` | The API root up to and including `/v1`; `/chat/completions` is appended. |
| `model` | `var model: String` | The model name or proxy alias. |
| `api_key` | `var api_key: String` | The bearer token; empty sends no `Authorization` header. |
| `max_tokens` | `var max_tokens: int` | The reply's `max_tokens`. |
| `display_name` | `display_name() -> String` | The model, or `LLM` without one. |
| `is_configured` | `is_configured() -> bool` | Base URL and model set; the key is optional (none sends no `Authorization`). |
| `setup_hint` | `setup_hint() -> String` | Names what to set. |
| `build_request` | `build_request(system: String, user: String, tools: Array) -> Dictionary` | System + user messages, tools as `{type: function, function: {...}}`, `tool_choice: auto`, bearer key. |
| `extract_tool_call` | `extract_tool_call(json: Variant) -> Variant` | The first call of the first choice. Arguments as a JSON string (parsed quietly) or an object; `''` reads as `{}`; a refusal or unparseable arguments are null. |

### LFLlmToolClient

| Member | Signature | Description |
|---|---|---|
| `_init` | `LFLlmToolClient.new(llm_provider: LFLlmProvider, request_interval_ms := 0, request_timeout_ms := DEFAULT_TIMEOUT_MS, response_byte_limit := DEFAULT_MAX_RESPONSE_BYTES, initial_clock_ms := Callable())` | Sets `provider`, `min_interval_ms`, `timeout_ms`, `max_response_bytes` and `clock_ms`. A timeout of 0 or less means no deadline (a negative one is stored as 0), as everywhere else in LF; leave it out for the default. A byte cap of 0 or less means no limit (as `max_body_bytes` of `LFHttp.request`; a negative one is stored as 0); leave it out for the default of 4 MiB. |
| `DEFAULT_TIMEOUT_MS` | `const DEFAULT_TIMEOUT_MS: int` | `30000`. |
| `DEFAULT_MAX_RESPONSE_BYTES` | `const DEFAULT_MAX_RESPONSE_BYTES: int` | `4 * 1024 * 1024`. |
| `provider` | `var provider: LFLlmProvider` | The provider requests go through. Replaceable at any time: a request in flight is still read by the provider that sent it. Null makes `call_tool` resolve to null. |
| `min_interval_ms` | `var min_interval_ms: int` | Milliseconds after a request starts before the next may start. |
| `timeout_ms` | `var timeout_ms: int` | Deadline for a whole request; 0 or less: none. |
| `max_response_bytes` | `var max_response_bytes: int` | Passed to `LFHttp.request` as `max_body_bytes`: a reply over this many bytes (by its declared length or what has arrived) fails the request, so `call_tool` resolves to null; 0 means no limit. |
| `clock_ms` | `var clock_ms: Callable` | Returns milliseconds for the interval; empty uses `Time.get_ticks_msec()`. May be replaced at any time. |
| `can_request_now` | `can_request_now() -> bool` | None in flight and the interval since the last request start has passed. |
| `is_in_flight` | `is_in_flight() -> bool` | A request awaits its reply. |
| `call_tool` | `call_tool(system: String, user: String, tools: Array) -> Variant` (await) | One request; resolves to `{name, input}`, or null on any failure (including a non-2xx/3xx status). A tool that fails `LFLlmTool.is_valid_tool`, or a provider whose `build_request` gives no `{url: String, headers: Dictionary, body: Dictionary}`, makes it resolve to null with a warning, sending nothing and starting no interval. |

### LFLlmTool (static)

| Member | Signature | Description |
|---|---|---|
| `define` | `static define(name: String, description: String, properties: Dictionary = {}, required: Array = []) -> Dictionary` | A tool with a closed object schema (deep-copied properties, `additionalProperties: false`). |
| `find_tool` | `static find_tool(tools: Array, name: String) -> Dictionary` | The tool with that name, or `{}` (check `is_empty()`: a model can name a tool it was not offered). Entries that are not Dictionaries or whose `name` is not a String are skipped. |
| `is_valid_tool` | `static is_valid_tool(tool: Variant) -> bool` | Whether `tool` is a Dictionary with a non-empty String `name`, a String `description` and a Dictionary `parameters`. The schema itself is not validated. |
| `coerce_args` | `static coerce_args(properties: Dictionary, input: Dictionary, skip: Array = []) -> Dictionary` | Only the schema's keys (minus `skip`), cast: integer → int, number → float, string → String, boolean → bool (also from a number or `'true'`/`'false'`); other types kept as is. Nulls and uncastable values (including a number with a fraction for an integer — `4.0` and `"4"` give 4, `2.9` and `"2.9"` are left out —, infinite or NaN numbers, numeric strings with an exponent beyond ±300, and integers beyond the 64-bit range) are left out. After the cast the schema's `enum`, `minimum`, `maximum` (inclusive) and `maxLength` are enforced: a value that breaks one is rejected (left out, not clamped) with a pushed warning naming the argument and the rule. Other schema keywords (`minLength`, `pattern`, `exclusiveMinimum`…) are not checked. |

## Usage

A longer example. Set the `ANTHROPIC_API_KEY` environment variable before starting Godot
(see Step by step, step 2; or use `LFOpenAiCompatibleProvider` with a local server), then:

```gdscript
# ai_opponent.gd: a script on the Node that runs the computer player.
extends Node

# The actions the model may pick from.
var tools := [
	LFLlmTool.define("move", "Move to a cell.",
			{"x": {"type": "integer"}, "y": {"type": "integer"}}, ["x", "y"]),
	LFLlmTool.define("wait", "Do nothing this turn."),
]
var provider := LFAnthropicProvider.new("claude-opus-5-5", "ANTHROPIC_API_KEY", 4096, "low")
# A local model instead (Ollama):
# var provider := LFOpenAiCompatibleProvider.new("http://localhost:11434/v1", "llama3.2")
var client := LFLlmToolClient.new(provider, 3000)   # at most one request every 3 s


# Call this on every turn. It does nothing while a request is pending or too recent.
func take_turn(board_description: String) -> void:
	var tool_call: Variant = await client.call_tool(
			"You control the blue team. Pick exactly one tool.", board_description, tools)
	if tool_call == null:
		return   # throttled, not configured, failed, refused, or picked no tool
	var tool := LFLlmTool.find_tool(tools, tool_call["name"])
	if tool.is_empty():
		return   # the model named a tool it was not offered
	# Keep only the declared arguments, converted to their types.
	var args := LFLlmTool.coerce_args(tool["parameters"]["properties"], tool_call["input"])
	match tool_call["name"]:
		"move":
			if args.has("x") and args.has("y"):
				print("Moving to ", args["x"], ", ", args["y"])
		"wait":
			print("Waiting")
```

## Notes

- A failed request, a malformed reply, an unconfigured provider or a malformed tool definition gives `null`, never a script error, so a caller may ask every frame. A failed request and a refused tool list log a warning each time; a failed request's warning quotes at most the first 300 characters of the server's reply text, line breaks escaped. The tools are checked before the provider builds the request; a provider subclass of your own that raises an error in `build_request` or `extract_tool_call` is not caught (GDScript cannot catch errors), though the client is left free for the next call when `build_request` fails. An unconfigured provider is warned about once; replacing it with another unconfigured one warns once more.
- `min_interval_ms` counts from when a request *starts*; one request is in flight at a time.
- **A freed clock fails closed.** If `clock_ms` can no longer be called (the object behind it was freed), `can_request_now()` is `false`, so `call_tool` makes no request, and an error is reported once.
- `timeout_ms` bounds the whole exchange (the request plus the full reply), so a server that stalls or sends its answer at a trickle cannot keep a request in flight. A reply above `max_response_bytes` fails the request (`LFHttp` stops reading it once the limit is passed).
- The request to Claude follows Anthropic's Messages API documentation (its headers, the `input_schema` field, `tool_choice: auto`, and the optional `effort` setting). The `beta` and `extra_body` arguments are sent as given and not checked: `beta` becomes the `anthropic-beta` header and `extra_body` is merged into the request body, so a value the API does not accept comes back as an API error. The provider always sends `tool_choice: auto` (it never forces a tool), so the model may answer without a tool call; that reads as null.
- What the tests cover: request building and response parsing for both providers against fixture JSON, and the client end to end against a local HTTP server (throttling, timeout, size cap, error status). No test calls a hosted API.
- Keys: read them from an environment variable or from a setting the player types in; never write one into a script, scene or project file, and never ship one inside an exported game (Step by step, step 2, explains why and how to set the variable).
- The key goes only to the provider's URL (`api_url`, or `base_url` + `/chat/completions`). Over `http://` it travels unencrypted, so use `https://` except for a server on your own machine. `LFHttp` follows redirects, drops the key's header when one leads to another origin, and refuses an `https` to `http` redirect.
