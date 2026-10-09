## The base class for talking to one language-model service: it builds the web request
## and reads the model's chosen tool back.
##
## Each subclass knows one API's wire format for tool calling (a tool call: the model
## answers by picking one of your tools and filling in its arguments). A caller hands a provider only
## neutral pieces — a system prompt, the user text, and tools as
## `{name, description, parameters}` where `parameters` is a JSON-schema object — and the
## provider turns them into an HTTP request (`build_request`) and reads the first tool call
## back out of the decoded JSON response (`extract_tool_call`).
##
## This base is never configured; extend it for each API (`LFAnthropicProvider`,
## `LFOpenAiCompatibleProvider`). Credentials and endpoints belong in the environment or
## the caller's settings, never in source.
class_name LFLlmProvider
extends RefCounted

## Tool key: the tool's name (also the name key of an extracted tool call).
const KEY_NAME := 'name'
## Tool key: what the tool does, for the model.
const KEY_DESCRIPTION := 'description'
## Tool key: the JSON-schema object describing the tool's arguments.
const KEY_PARAMETERS := 'parameters'
## Tool-call key: the arguments Dictionary the model filled in.
const KEY_INPUT := 'input'
## Request key: the endpoint URL.
const KEY_URL := 'url'
## Request key: the HTTP headers Dictionary.
const KEY_HEADERS := 'headers'
## Request key: the body Dictionary, sent as JSON.
const KEY_BODY := 'body'

## Generic name the base reports from `display_name()` (also a subclass's fallback).
const _GENERIC_DISPLAY_NAME := 'LLM'


## Returns a short name for logs and menus. The base returns `LLM`.
func display_name() -> String:
	return _GENERIC_DISPLAY_NAME


## Returns `true` when a request could be made right now: the key, endpoint and model it
## needs are all set. The base returns `false`.
func is_configured() -> bool:
	return false


## Returns what a user has to set for `is_configured()` to become true. The base returns
## an empty String.
func setup_hint() -> String:
	return ''


## Returns `{url: String, headers: Dictionary, body: Dictionary}` for one request from a
## system prompt (standing instructions), the user text and the tools. `body` is sent as
## JSON. The base returns `{}`; subclasses override it.
func build_request(_system: String, _user: String, _tools: Array) -> Dictionary:
	return {}


## Returns the first tool call in a decoded response as `{name: String, input: Dictionary}`, or
## null when there is none: no call, a refusal, or a malformed response. The base returns
## null. The response is untrusted, so an override must not raise on any input: check each
## field's type before comparing it (comparing a String with a number is a script error).
func extract_tool_call(_json: Variant) -> Variant:
	return null
