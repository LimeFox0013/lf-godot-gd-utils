## Talks to any language-model server that speaks the OpenAI Chat Completions format, for
## tool calling.
##
## An `LFLlmProvider` for OpenAI itself, a LiteLLM proxy, or a local server such as Ollama or LM Studio. `base_url` is the
## API root up to and including `/v1` (`/chat/completions` is appended); `api_key` is sent
## as a bearer token and may be empty, since a local server needs none.
class_name LFOpenAiCompatibleProvider
extends LFLlmProvider

static var _log := LFLogger.new(['[LFOpenAiCompatibleProvider]'])

## The default reply limit in tokens: the request's `max_tokens`.
const DEFAULT_MAX_TOKENS := 4096

## Path appended to `base_url`.
const _COMPLETIONS_PATH := '/chat/completions'
## Separator trimmed from the end of `base_url`.
const _SLASH := '/'
## Header naming the body's media type.
const _HEADER_CONTENT_TYPE := 'Content-Type'
## Media type of the JSON body.
const _JSON_MEDIA_TYPE := 'application/json'
## Header carrying the bearer token.
const _HEADER_AUTHORIZATION := 'Authorization'
## Value format of the Authorization header.
const _BEARER_FORMAT := 'Bearer %s'
## Key naming the kind of a tool entry.
const _KEY_TYPE := 'type'
## Tool entry type, and the key holding a function's definition or call.
const _FUNCTION := 'function'
## Body key: the model name.
const _KEY_MODEL := 'model'
## Body key: the reply limit in tokens.
const _KEY_MAX_TOKENS := 'max_tokens'
## Body key: the conversation messages.
const _KEY_MESSAGES := 'messages'
## Message key: who wrote it.
const _KEY_ROLE := 'role'
## Role of the system prompt.
const _ROLE_SYSTEM := 'system'
## Role of the user's message.
const _ROLE_USER := 'user'
## Message key: the text.
const _KEY_CONTENT := 'content'
## Body key: the tool list.
const _KEY_TOOLS := 'tools'
## Body key: how the model must choose a tool.
const _KEY_TOOL_CHOICE := 'tool_choice'
## Tool choice letting the model pick any tool.
const _TOOL_CHOICE_AUTO := 'auto'
## Response key: the list of answers.
const _KEY_CHOICES := 'choices'
## Choice key: the answer message.
const _KEY_MESSAGE := 'message'
## Message key: the refusal text, when refused.
const _KEY_REFUSAL := 'refusal'
## Message key: the tool calls.
const _KEY_TOOL_CALLS := 'tool_calls'
## Function key: the arguments (a JSON string or an object).
const _KEY_ARGUMENTS := 'arguments'

## The API root, e.g. `http://localhost:4000/v1`.
var base_url: String
## The model name or proxy alias to request.
var model: String
## The bearer token; empty sends no `Authorization` header.
var api_key: String
## The most tokens (word pieces) the reply may use: the request's `max_tokens`.
var max_tokens: int


## Creates a provider for the API root `api_root` (up to and including `/v1`), requesting
## `model_name` with the bearer token `key` (empty for none) and `token_limit` as
## `max_tokens`. With an empty root or model it is not configured.
func _init(api_root := '', model_name := '', key := '', token_limit := DEFAULT_MAX_TOKENS) -> void:
	base_url = api_root
	model = model_name
	api_key = key
	max_tokens = token_limit


## Returns the model name, or `LLM` without one.
func display_name() -> String:
	return model if model != '' else _GENERIC_DISPLAY_NAME


## Returns `true` when both the base URL and the model are set; the key is optional.
func is_configured() -> bool:
	return base_url != '' and model != ''


## Returns a sentence naming what to set.
func setup_hint() -> String:
	return 'Set a base URL and a model (and an API key if the endpoint needs one).'


## Returns a `/chat/completions` request: system and user messages, tools as `function` entries,
## `tool_choice: auto`.
func build_request(system: String, user: String, tools: Array) -> Dictionary:
	var functions := []
	for tool: Variant in tools:
		functions.append({
			_KEY_TYPE: _FUNCTION,
			_FUNCTION: {KEY_NAME: tool[KEY_NAME], KEY_DESCRIPTION: tool[KEY_DESCRIPTION], KEY_PARAMETERS: tool[KEY_PARAMETERS]},
		})
	var headers := {_HEADER_CONTENT_TYPE: _JSON_MEDIA_TYPE}
	if api_key != '':
		headers[_HEADER_AUTHORIZATION] = _BEARER_FORMAT % api_key
	return {
		KEY_URL: base_url.trim_suffix(_SLASH) + _COMPLETIONS_PATH,
		KEY_HEADERS: headers,
		KEY_BODY: {
			_KEY_MODEL: model,
			_KEY_MAX_TOKENS: max_tokens,
			_KEY_MESSAGES: [
				{_KEY_ROLE: _ROLE_SYSTEM, _KEY_CONTENT: system},
				{_KEY_ROLE: _ROLE_USER, _KEY_CONTENT: user},
			],
			_KEY_TOOLS: functions,
			_KEY_TOOL_CHOICE: _TOOL_CHOICE_AUTO,
		},
	}


## Returns the first function call of the first choice as `{name, input}`. Arguments may arrive as
## a JSON string (parsed quietly) or as an object; an empty string reads as `{}`. Null for
## a refusal (logged as a warning), no call, unparseable arguments, or a malformed response.
func extract_tool_call(json: Variant) -> Variant:
	if not json is Dictionary:
		return null
	var choices: Variant = json.get(_KEY_CHOICES)
	if not choices is Array or choices.is_empty() or not choices[0] is Dictionary:
		return null
	var message: Variant = choices[0].get(_KEY_MESSAGE)
	if not message is Dictionary:
		return null
	var refusal: Variant = message.get(_KEY_REFUSAL)
	if refusal is String and refusal != '':
		_log.warning('request refused')
		return null
	var tool_calls: Variant = message.get(_KEY_TOOL_CALLS)
	if not tool_calls is Array:
		return null
	for tool_call: Variant in tool_calls:
		if not tool_call is Dictionary or not tool_call.get(_FUNCTION) is Dictionary:
			continue
		var function: Dictionary = tool_call[_FUNCTION]
		var arguments: Variant = function.get(_KEY_ARGUMENTS, {})
		if arguments is String:
			arguments = {} if arguments == '' else LFJson.parse(arguments)
		if not arguments is Dictionary:
			return null
		return {KEY_NAME: str(function.get(KEY_NAME, '')), KEY_INPUT: arguments}
	return null
