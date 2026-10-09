## Talks to Claude (Anthropic's language model) for tool calling.
##
## An `LFLlmProvider` for the Anthropic Messages API (`POST /v1/messages`).
## The API key is read from the environment variable `api_key_env` on every call (trimmed
## of surrounding whitespace), so setting it mid-session takes effect. The model is always passed in.
##
## Optional pieces are sent only when set: `effort` becomes `output_config.effort`, `beta`
## the `anthropic-beta` header, and `extra_body` is merged into the body last (both are
## sent as given and not checked). Tools go out with `tool_choice`
## `auto`; a response whose `stop_reason` is `refusal` reads as no tool call.
class_name LFAnthropicProvider
extends LFLlmProvider

static var _log := LFLogger.new(['[LFAnthropicProvider]'])

## The Messages endpoint.
const API_URL := 'https://api.anthropic.com/v1/messages'
## The `anthropic-version` header value.
const API_VERSION := '2023-06-01'
## The default environment variable holding the API key.
const DEFAULT_API_KEY_ENV := 'ANTHROPIC_API_KEY'
## The default reply limit in tokens: the request's `max_tokens`.
const DEFAULT_MAX_TOKENS := 4096

## Name reported from `display_name()`.
const _DISPLAY_NAME := 'Claude'
## Header naming the body's media type.
const _HEADER_CONTENT_TYPE := 'Content-Type'
## Media type of the JSON body.
const _JSON_MEDIA_TYPE := 'application/json'
## Header carrying the API key.
const _HEADER_API_KEY := 'x-api-key'
## Header carrying `API_VERSION`.
const _HEADER_VERSION := 'anthropic-version'
## Header carrying `beta`.
const _HEADER_BETA := 'anthropic-beta'
## Body key: the model id.
const _KEY_MODEL := 'model'
## Body key: the reply limit in tokens.
const _KEY_MAX_TOKENS := 'max_tokens'
## Body key: the system prompt.
const _KEY_SYSTEM := 'system'
## Body key: the tool list.
const _KEY_TOOLS := 'tools'
## Tool key: the argument schema.
const _KEY_INPUT_SCHEMA := 'input_schema'
## Body key: how the model must choose a tool.
const _KEY_TOOL_CHOICE := 'tool_choice'
## Key naming the kind of a tool choice or content block.
const _KEY_TYPE := 'type'
## Tool choice letting the model pick any tool.
const _TOOL_CHOICE_AUTO := 'auto'
## Body key: the conversation messages.
const _KEY_MESSAGES := 'messages'
## Message key: who wrote it.
const _KEY_ROLE := 'role'
## Role of the user's message.
const _ROLE_USER := 'user'
## Message and response key: the content.
const _KEY_CONTENT := 'content'
## Body key: output settings.
const _KEY_OUTPUT_CONFIG := 'output_config'
## Output-settings key: the effort level.
const _KEY_EFFORT := 'effort'
## Response key: why the model stopped.
const _KEY_STOP_REASON := 'stop_reason'
## Stop reason of a refused request.
const _STOP_REFUSAL := 'refusal'
## Content block type of a tool call.
const _BLOCK_TOOL_USE := 'tool_use'

## The model id, e.g. `claude-opus-5-5`.
var model: String
## The environment variable read for the API key.
var api_key_env: String
## The most tokens (word pieces) the reply may use: the request's `max_tokens`.
var max_tokens: int
## `output_config.effort` (`low` … `max`); empty leaves it out.
var effort: String
## The `anthropic-beta` header; empty leaves it out.
var beta: String
## Extra top-level body fields, merged in last (they override the built ones).
var extra_body: Dictionary
## The endpoint; replaceable for a proxy or a test server.
var api_url := API_URL


## Creates a provider for `model_id` that reads its API key from the environment variable
## `key_env_var`. `token_limit` sets `max_tokens`, `effort_level` sets `effort`,
## `beta_header` sets `beta`, and `extra_fields` (deep-copied) sets `extra_body`; empty ones
## are left out of the request.
func _init(model_id: String, key_env_var := DEFAULT_API_KEY_ENV, token_limit := DEFAULT_MAX_TOKENS, effort_level := '', beta_header := '', extra_fields := {}) -> void:
	model = model_id
	api_key_env = key_env_var
	max_tokens = token_limit
	effort = effort_level
	beta = beta_header
	extra_body = extra_fields.duplicate(true)


## The key from the environment, trimmed: a trailing newline would fail the request
## ("Invalid header") and a blank value is no key.
func _api_key() -> String:
	return OS.get_environment(api_key_env).strip_edges()


## Returns `Claude`.
func display_name() -> String:
	return _DISPLAY_NAME


## Returns `true` when the model is set and the key's environment variable is not blank.
func is_configured() -> bool:
	return model != '' and _api_key() != ''


## Returns a sentence naming the environment variable to set.
func setup_hint() -> String:
	return 'Set %s to use Claude.' % api_key_env


## Returns the Messages request: `x-api-key`, `anthropic-version` (and `anthropic-beta`) headers;
## `model`, `max_tokens`, `system`, the tools with `input_schema`, `tool_choice: auto` and
## one user message in the body.
func build_request(system: String, user: String, tools: Array) -> Dictionary:
	var anthropic_tools := []
	for tool: Variant in tools:
		anthropic_tools.append({KEY_NAME: tool[KEY_NAME], KEY_DESCRIPTION: tool[KEY_DESCRIPTION], _KEY_INPUT_SCHEMA: tool[KEY_PARAMETERS]})
	var headers := {
		_HEADER_CONTENT_TYPE: _JSON_MEDIA_TYPE,
		_HEADER_API_KEY: _api_key(),
		_HEADER_VERSION: API_VERSION,
	}
	if beta != '':
		headers[_HEADER_BETA] = beta
	var body := {
		_KEY_MODEL: model,
		_KEY_MAX_TOKENS: max_tokens,
		_KEY_SYSTEM: system,
		_KEY_TOOLS: anthropic_tools,
		_KEY_TOOL_CHOICE: {_KEY_TYPE: _TOOL_CHOICE_AUTO},
		_KEY_MESSAGES: [{_KEY_ROLE: _ROLE_USER, _KEY_CONTENT: user}],
	}
	if effort != '':
		body[_KEY_OUTPUT_CONFIG] = {_KEY_EFFORT: effort}
	body.merge(extra_body.duplicate(true), true)
	return {KEY_URL: api_url, KEY_HEADERS: headers, KEY_BODY: body}


## Returns the first `tool_use` content block as `{name, input}`; null for a refusal (logged as a
## warning), no tool use, or a malformed response. A non-Dictionary `input` reads as `{}`.
func extract_tool_call(json: Variant) -> Variant:
	if not json is Dictionary:
		return null
	# Every field is checked for its type before it is compared: comparing a String with a
	# number raises a script error.
	var stop_reason: Variant = json.get(_KEY_STOP_REASON)
	if stop_reason is String and stop_reason == _STOP_REFUSAL:
		_log.warning('request refused')
		return null
	var content: Variant = json.get(_KEY_CONTENT)
	if not content is Array:
		return null
	for block: Variant in content:
		if not block is Dictionary:
			continue
		var type: Variant = block.get(_KEY_TYPE)
		if type is String and type == _BLOCK_TOOL_USE:
			var input: Variant = block.get(KEY_INPUT, {})
			return {KEY_NAME: str(block.get(KEY_NAME, '')), KEY_INPUT: input if input is Dictionary else {}}
	return null
