[
  # Known false positive: Ecto.Multi uses MapSet opaque type internally
  # https://github.com/elixir-ecto/ecto/issues/3803
  {"lib/blackboex/accounts.ex", :call_without_opaque},
  {"lib/blackboex/organizations.ex", :call_without_opaque},
  # ReqLLM uses defdelegate with default args — Dialyzer can't resolve delegated functions
  {"lib/blackboex/llm/req_llm_client.ex", :unknown_function},
  # ExRated is an OTP app started at runtime — not visible to Dialyzer at compile time
  {"lib/blackboex/llm/rate_limiter.ex", :unknown_function},
  # Ecto.Multi opaque type false positive in versioning
  {"lib/blackboex/apis.ex", :call_without_opaque},
  # Ecto.Multi opaque type false positive in conversations
  {"lib/blackboex/apis/conversations.ex", :call_without_opaque},
  # Ecto.Multi opaque type false positive in key rotation
  {"lib/blackboex/apis/keys.ex", :call_without_opaque},
  # LiveMonacoEditor is an external dep — Dialyzer can't resolve HEEx component calls
  {"lib/blackboex_web/live/api_live/edit.ex", :unknown_function},
  # Hammer uses `use Hammer` macro with defdelegate — Dialyzer can't resolve delegated functions
  {"lib/blackboex_web/rate_limiter_backend.ex", :unknown_function},
  {"lib/blackboex_web/rate_limiter_backend.ex", :callback_info_missing},
  # ExJsonSchema and Ymlr are in domain app deps — cross-app deps not visible to Dialyzer
  {"lib/blackboex/testing/contract_validator.ex", :unknown_function},
  {"lib/blackboex/docs/open_api_generator.ex", :unknown_function}
]
