[
  # Known false positive: Ecto.Multi uses MapSet opaque type internally
  # https://github.com/elixir-ecto/ecto/issues/3803
  {"lib/blackboex/accounts.ex", :call_without_opaque},
  {"lib/blackboex/organizations.ex", :call_without_opaque},
  # Ecto.Multi opaque type false positive in versioning
  {"lib/blackboex/apis/versions.ex", :call_without_opaque},
  # Ecto.Multi opaque type false positive in key rotation
  {"lib/blackboex/apis/keys.ex", :call_without_opaque},
  # Ecto.Multi opaque type false positive in Billing context
  {"lib/blackboex/billing.ex", :call_without_opaque},
  # Ecto.Multi opaque type false positive in Projects context
  {"lib/blackboex/projects.ex", :call_without_opaque},
  # Stripity Stripe uses complex internal types — Dialyzer can't fully resolve Live client
  {"lib/blackboex/billing/stripe_client/live.ex", :invalid_contract},
  {"lib/blackboex/billing/stripe_client/live.ex", :no_return},
  {"lib/blackboex/billing/stripe_client/live.ex", :call}
]
