[
  # Known false positive: Ecto.Multi uses MapSet opaque type internally
  # https://github.com/elixir-ecto/ecto/issues/3803
  {"lib/blackboex/accounts.ex", :call_without_opaque},
  {"lib/blackboex/organizations.ex", :call_without_opaque},
  # Ecto.Multi opaque type false positive in versioning
  {"lib/blackboex/apis/versions.ex", :call_without_opaque},
  # Ecto.Multi opaque type false positive in key rotation
  {"lib/blackboex/apis/keys.ex", :call_without_opaque},
  # Ecto.Multi opaque type false positive in Projects context
  {"lib/blackboex/projects.ex", :call_without_opaque},
  # Phoenix LiveComponent + defp component functions with attr declarations: the
  # __phoenix_component_verify__/1 function generated at line 1 contains `root: false`
  # map values that Dialyzer misreads as a dead `false` pattern match.
  # This is a known false positive in the Phoenix.Component.Declarative machinery
  # when a LiveComponent defines private function components with `attr` declarations.
  {"lib/blackboex_web/components/sidebar_tree_component.ex", :pattern_match},
  # Cloak library internals: `Cloak.Vault.read_config/1` and `decrypt!/2`
  # are only defined on concrete vault modules via `use Cloak.Vault`, but
  # Cloak's own code references them through the behaviour name — Dialyzer
  # analyzes the library without the concrete vault's PLT info and can't
  # resolve them.
  ~r{deps/cloak/lib/cloak/vault\.ex.*:unknown_function},
  # Cloak.Ecto.Type + Cloak.Vault declare @callback without matching
  # behaviour_info/1 the PLT can resolve. Library-side false positives
  # visible from the lib directory and from the embedded gen_server.ex
  # (whose path is a tempdir in the Elixir distribution).
  ~r{deps/cloak_ecto/lib/cloak_ecto/type\.ex.*:callback_info_missing},
  ~r{gen_server\.ex.*:callback_info_missing}
]
