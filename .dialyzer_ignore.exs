[
  # Known false positive: Ecto.Multi uses MapSet opaque type internally
  # https://github.com/elixir-ecto/ecto/issues/3803
  {"lib/blackboex/accounts.ex", :call_without_opaque},
  {"lib/blackboex/organizations.ex", :call_without_opaque},
  # ReqLLM uses defdelegate with default args — Dialyzer can't resolve delegated functions
  {"lib/blackboex/llm/req_llm_client.ex", :unknown_function},
  # ExRated is an OTP app started at runtime — not visible to Dialyzer at compile time
  {"lib/blackboex/llm/rate_limiter.ex", :unknown_function}
]
