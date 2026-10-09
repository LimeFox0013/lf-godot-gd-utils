extends GutTest

## The Messages API wire format only — no network call.

const ENV := 'LF_TEST_ANTHROPIC_KEY'
const TOOLS := [{'name': 'finish', 'description': 'Finish the task.', 'parameters': {'type': 'object', 'properties': {}}}]

var provider: LFAnthropicProvider


func before_each():
	OS.set_environment(ENV, '')
	provider = LFAnthropicProvider.new('some-model', ENV)


func after_each():
	OS.unset_environment(ENV)


func test_it_is_configured_exactly_when_the_api_key_is_set():
	assert_false(provider.is_configured())
	assert_string_contains(provider.setup_hint(), ENV)

	OS.set_environment(ENV, 'test-key')
	assert_true(provider.is_configured())


func test_a_key_with_surrounding_whitespace_is_sent_trimmed_and_blank_is_no_key():
	OS.set_environment(ENV, '  sk-test\n')
	assert_eq(provider.build_request('s', 'u', TOOLS)['headers']['x-api-key'], 'sk-test')
	OS.set_environment(ENV, ' \n')
	assert_false(provider.is_configured())


func test_it_needs_a_model():
	OS.set_environment(ENV, 'test-key')
	assert_false(LFAnthropicProvider.new('', ENV).is_configured())


func test_the_key_is_read_from_the_default_variable_unless_told_otherwise():
	assert_eq(LFAnthropicProvider.new('m').api_key_env, 'ANTHROPIC_API_KEY')
	assert_eq(LFAnthropicProvider.DEFAULT_API_KEY_ENV, 'ANTHROPIC_API_KEY')


func test_the_display_name_and_the_constructor_fields():
	var tuned := LFAnthropicProvider.new('some-model', ENV, 2048, 'high', 'some-beta', {'k': 1})

	assert_eq(tuned.display_name(), 'Claude')
	assert_eq([tuned.model, tuned.api_key_env, tuned.max_tokens, tuned.effort, tuned.beta, tuned.extra_body], ['some-model', ENV, 2048, 'high', 'some-beta', {'k': 1}])
	assert_eq(tuned.api_url, LFAnthropicProvider.API_URL)


func test_the_request_carries_the_key_the_prompt_and_tools_as_input_schemas():
	OS.set_environment(ENV, 'test-key')

	var request := provider.build_request('System text.', 'User text.', TOOLS)

	assert_eq(request['url'], LFAnthropicProvider.API_URL)
	assert_eq(request['headers']['x-api-key'], 'test-key')
	assert_eq(request['headers']['anthropic-version'], '2023-06-01')
	assert_eq(request['body']['model'], 'some-model')
	assert_eq(request['body']['max_tokens'], 4096)
	assert_eq(request['body']['system'], 'System text.')
	assert_eq(request['body']['messages'], [{'role': 'user', 'content': 'User text.'}])
	assert_eq(request['body']['tools'], [{'name': 'finish', 'description': 'Finish the task.', 'input_schema': TOOLS[0]['parameters']}])
	assert_eq(request['body']['tool_choice'], {'type': 'auto'})


func test_optional_pieces_are_left_out_unless_set():
	var request := provider.build_request('s', 'u', TOOLS)

	assert_false(request['headers'].has('anthropic-beta'))
	assert_false(request['body'].has('output_config'))
	assert_false(request['body'].has('some_field'))


func test_effort_beta_and_extra_body_are_sent_when_set():
	var tuned := LFAnthropicProvider.new('some-model', ENV, 2048, 'low', 'some-beta-header', {'some_field': 'value'})

	var request := tuned.build_request('s', 'u', TOOLS)

	assert_eq(request['headers']['anthropic-beta'], 'some-beta-header')
	assert_eq(request['body']['output_config'], {'effort': 'low'})
	assert_eq(request['body']['some_field'], 'value')
	assert_eq(request['body']['max_tokens'], 2048)


func test_extra_body_overrides_the_built_fields_and_is_copied():
	var extra := {'max_tokens': 16, 'metadata': {'user_id': 'u'}}
	var tuned := LFAnthropicProvider.new('some-model', ENV, 4096, '', '', extra)
	extra['metadata']['user_id'] = 'changed'

	var body: Dictionary = tuned.build_request('s', 'u', TOOLS)['body']
	body['metadata']['user_id'] = 'mutated'

	assert_eq(body['max_tokens'], 16)
	assert_eq(tuned.build_request('s', 'u', TOOLS)['body']['metadata'], {'user_id': 'u'})


func test_the_endpoint_can_be_replaced():
	provider.api_url = 'http://127.0.0.1:9/v1/messages'
	assert_eq(provider.build_request('s', 'u', [])['url'], 'http://127.0.0.1:9/v1/messages')


func test_it_reads_the_first_tool_use_block():
	var json := {'stop_reason': 'tool_use', 'content': [
		{'type': 'text', 'text': 'Calling it now.'},
		{'type': 'tool_use', 'name': 'finish', 'input': {}},
		{'type': 'tool_use', 'name': 'other', 'input': {}},
	]}

	assert_eq(provider.extract_tool_call(json), {'name': 'finish', 'input': {}})


func test_a_non_object_input_reads_as_empty():
	var json := {'content': [{'type': 'tool_use', 'name': 'finish', 'input': 'x'}]}
	assert_eq(provider.extract_tool_call(json), {'name': 'finish', 'input': {}})


func test_no_tool_call_a_refusal_or_a_malformed_response_is_null():
	assert_null(provider.extract_tool_call({'stop_reason': 'end_turn', 'content': [{'type': 'text', 'text': 'Nothing to do.'}]}))
	assert_null(provider.extract_tool_call({'stop_reason': 'refusal', 'content': [{'type': 'tool_use', 'name': 'finish', 'input': {}}]}))
	assert_null(provider.extract_tool_call('not a dictionary'))
	assert_null(provider.extract_tool_call({'content': 'not an array'}))


func test_the_constants_name_the_messages_api():
	assert_eq(LFAnthropicProvider.API_URL, 'https://api.anthropic.com/v1/messages')
	assert_eq(LFAnthropicProvider.API_VERSION, '2023-06-01')
	assert_eq(LFAnthropicProvider.DEFAULT_API_KEY_ENV, 'ANTHROPIC_API_KEY')
	assert_eq(LFAnthropicProvider.DEFAULT_MAX_TOKENS, 4096)
	assert_eq(LFAnthropicProvider.new('m').max_tokens, LFAnthropicProvider.DEFAULT_MAX_TOKENS)


func test_a_refusal_is_reported_as_a_warning():
	assert_null(provider.extract_tool_call({'stop_reason': 'refusal', 'content': []}))
	assert_push_warning('request refused')


func test_blocks_that_are_not_tool_calls_are_skipped_and_a_missing_name_reads_as_empty():
	var json := {'content': ['junk', {'type': 'text'}, {'type': 'tool_use', 'input': {'a': 1}}]}
	assert_eq(provider.extract_tool_call(json), {'name': '', 'input': {'a': 1}})
	assert_eq(provider.extract_tool_call({'content': [{'type': 'tool_use', 'name': 'finish'}]}), {'name': 'finish', 'input': {}}, 'a missing input reads as empty')
	assert_null(provider.extract_tool_call({'stop_reason': 'tool_use'}), 'no content at all')
	assert_push_warning_count(0, 'only a refusal is reported')


## Fields of a reply are untrusted: a number where the API sends text is malformed, never a
## script error.
func test_wrongly_typed_fields_read_as_no_call_without_an_error():
	assert_null(provider.extract_tool_call({'stop_reason': 5, 'content': []}))
	assert_null(provider.extract_tool_call({'content': [{'type': 1}]}))
	assert_null(provider.extract_tool_call({'stop_reason': [], 'content': [{'type': {}}, {'type': null}]}))
	assert_eq(provider.extract_tool_call({'stop_reason': 5, 'content': [{'type': 1}, {'type': 'tool_use', 'name': 'go', 'input': {}}]}), {'name': 'go', 'input': {}}, 'a later valid block is still found')
	assert_engine_error_count(0)
