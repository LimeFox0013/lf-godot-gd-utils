extends GutTest

## The Chat Completions wire format — no network call.

const TOOLS := [{'name': 'finish', 'description': 'Finish the task.', 'parameters': {'type': 'object', 'properties': {}}}]


func _provider(api_key := 'proxy-key') -> LFOpenAiCompatibleProvider:
	return LFOpenAiCompatibleProvider.new('http://localhost:4000/v1/', 'proxy-alias', api_key)


func _response(message: Dictionary) -> Dictionary:
	return {'choices': [{'index': 0, 'message': message, 'finish_reason': 'tool_calls'}]}


func test_it_needs_a_base_url_and_a_model_but_not_a_key():
	assert_true(LFOpenAiCompatibleProvider.new('http://localhost:11434/v1', 'llama', '').is_configured(), 'a local server needs no key')
	assert_false(LFOpenAiCompatibleProvider.new('', 'llama', 'key').is_configured())
	assert_false(LFOpenAiCompatibleProvider.new('http://localhost:4000/v1', '', 'key').is_configured())
	assert_ne(LFOpenAiCompatibleProvider.new().setup_hint(), '')


func test_the_display_name_is_the_model():
	assert_eq(_provider().display_name(), 'proxy-alias')
	assert_eq(LFOpenAiCompatibleProvider.new().display_name(), 'LLM')


func test_the_request_posts_chat_completions_with_tools_as_functions():
	var request := _provider().build_request('System text.', 'User text.', TOOLS)

	assert_eq(request['url'], 'http://localhost:4000/v1/chat/completions')
	assert_eq(request['headers']['Authorization'], 'Bearer proxy-key')
	assert_eq(request['body']['model'], 'proxy-alias')
	assert_eq(request['body']['max_tokens'], 4096)
	assert_eq(request['body']['messages'], [
		{'role': 'system', 'content': 'System text.'},
		{'role': 'user', 'content': 'User text.'},
	])
	assert_eq(request['body']['tools'], [{'type': 'function', 'function': {'name': 'finish', 'description': 'Finish the task.', 'parameters': TOOLS[0]['parameters']}}])
	assert_eq(request['body']['tool_choice'], 'auto')


func test_the_constructor_fields():
	var provider := LFOpenAiCompatibleProvider.new('http://h/v1', 'm', 'k', 512)

	assert_eq([provider.base_url, provider.model, provider.api_key, provider.max_tokens], ['http://h/v1', 'm', 'k', 512])
	assert_eq(provider.build_request('s', 'u', [])['body']['max_tokens'], 512)


func test_no_authorization_header_without_a_key():
	var request := _provider('').build_request('s', 'u', TOOLS)

	assert_false(request['headers'].has('Authorization'))


func test_it_reads_the_first_tool_call_and_parses_its_arguments():
	var json := _response({'role': 'assistant', 'content': null, 'tool_calls': [
		{'id': 'call_1', 'type': 'function', 'function': {'name': 'set_volume', 'arguments': '{"level": 2}'}},
		{'id': 'call_2', 'type': 'function', 'function': {'name': 'finish', 'arguments': '{}'}},
	]})

	assert_eq(_provider().extract_tool_call(json), {'name': 'set_volume', 'input': {'level': 2.0}})


func test_arguments_sent_as_an_object_or_an_empty_string_are_accepted_too():
	var as_object := _response({'tool_calls': [{'type': 'function', 'function': {'name': 'finish', 'arguments': {}}}]})
	var as_empty := _response({'tool_calls': [{'type': 'function', 'function': {'name': 'finish', 'arguments': ''}}]})

	assert_eq(_provider().extract_tool_call(as_object), {'name': 'finish', 'input': {}})
	assert_eq(_provider().extract_tool_call(as_empty), {'name': 'finish', 'input': {}})


func test_no_tool_call_a_refusal_or_a_malformed_response_is_null():
	var provider := _provider()
	assert_null(provider.extract_tool_call(_response({'role': 'assistant', 'content': 'Nothing to do.'})))
	assert_null(provider.extract_tool_call(_response({'refusal': 'I cannot help with that.', 'content': null})))
	assert_null(provider.extract_tool_call(_response({'tool_calls': [{'function': {'name': 'finish', 'arguments': 'not json'}}]})))
	assert_null(provider.extract_tool_call({'choices': []}))
	assert_null(provider.extract_tool_call('not a dictionary'))


func test_a_call_without_a_function_object_is_skipped():
	var json := _response({'tool_calls': ['junk', {'type': 'function'}, {'function': {'name': 'finish', 'arguments': '{}'}}]})

	assert_eq(_provider().extract_tool_call(json), {'name': 'finish', 'input': {}})


func test_the_default_token_limit():
	assert_eq(LFOpenAiCompatibleProvider.DEFAULT_MAX_TOKENS, 4096)
	assert_eq(LFOpenAiCompatibleProvider.new().max_tokens, LFOpenAiCompatibleProvider.DEFAULT_MAX_TOKENS)


func test_a_refusal_is_reported_and_an_empty_refusal_is_not_one():
	var provider := _provider()
	assert_null(provider.extract_tool_call(_response({'refusal': 'No.'})))
	assert_push_warning('request refused')
	var call := _response({'refusal': '', 'tool_calls': [{'function': {'name': 'finish', 'arguments': '{}'}}]})
	assert_eq(provider.extract_tool_call(call), {'name': 'finish', 'input': {}})
	assert_push_warning_count(1)


func test_every_malformed_layer_of_the_response_reads_as_no_call():
	var provider := _provider()
	assert_null(provider.extract_tool_call({}), 'no choices')
	assert_null(provider.extract_tool_call({'choices': ['junk']}), 'a choice that is not an object')
	assert_null(provider.extract_tool_call({'choices': [{'message': 'text'}]}), 'a message that is not an object')
	assert_null(provider.extract_tool_call(_response({'tool_calls': 'none'})), 'tool_calls that are not a list')
	assert_null(provider.extract_tool_call(_response({'tool_calls': []})))
	assert_null(provider.extract_tool_call(_response({'tool_calls': [{'function': {'name': 'finish', 'arguments': '[1, 2]'}}]})), 'arguments that are not an object')
	assert_null(provider.extract_tool_call(_response({'tool_calls': [{'function': {'name': 'finish', 'arguments': 7}}]})))
	assert_engine_error_count(0, 'unparseable arguments are read quietly')


func test_a_call_without_arguments_or_a_name_reads_as_empty():
	var json := _response({'tool_calls': [{'function': {}}]})
	assert_eq(_provider().extract_tool_call(json), {'name': '', 'input': {}})


func test_a_base_url_without_a_trailing_slash_gets_the_path_appended_once():
	var provider := LFOpenAiCompatibleProvider.new('http://localhost:11434/v1', 'llama')
	assert_eq(provider.build_request('s', 'u', [])['url'], 'http://localhost:11434/v1/chat/completions')


## Fields of a reply are untrusted: wrong types read as no call, never a script error.
func test_wrongly_typed_fields_read_as_no_call_without_an_error():
	for message in [{'refusal': 5}, {'refusal': 5, 'tool_calls': 7}, {'tool_calls': [{'function': {'arguments': 5}}]}, {'tool_calls': [{'function': {'arguments': '[1]'}}]}]:
		assert_null(_provider().extract_tool_call({'choices': [{'message': message}]}), str(message))
	assert_engine_error_count(0)
