extends GutTest


func test_the_base_provider_is_never_configured_and_reads_no_call():
	var provider := LFLlmProvider.new()

	assert_eq(provider.display_name(), 'LLM')
	assert_false(provider.is_configured())
	assert_eq(provider.setup_hint(), '')
	assert_eq(provider.build_request('s', 'u', []), {})
	assert_null(provider.extract_tool_call({'content': []}))


func test_a_client_on_the_base_provider_makes_no_request():
	var client := LFLlmToolClient.new(LFLlmProvider.new())

	assert_null(await client.call_tool('s', 'u', []))
	assert_null(await client.call_tool('s', 'u', []), 'asking again stays quiet and null')
	assert_false(client.is_in_flight())


func test_the_key_constants_name_the_neutral_wire_shape():
	assert_eq([LFLlmProvider.KEY_NAME, LFLlmProvider.KEY_DESCRIPTION, LFLlmProvider.KEY_PARAMETERS, LFLlmProvider.KEY_INPUT],
			['name', 'description', 'parameters', 'input'])
	assert_eq([LFLlmProvider.KEY_URL, LFLlmProvider.KEY_HEADERS, LFLlmProvider.KEY_BODY], ['url', 'headers', 'body'])
