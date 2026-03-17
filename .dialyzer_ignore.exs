[
  # Known false positive: Ecto.Multi uses MapSet opaque type internally
  # https://github.com/elixir-ecto/ecto/issues/3803
  {"lib/blackboex/accounts.ex", :call_without_opaque},
  {"lib/blackboex/organizations.ex", :call_without_opaque}
]
