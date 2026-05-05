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
  # Mix tasks are compile-time/dev tooling and are not part of the runtime PLT.
  ~r{lib/mix/tasks/blackboex\.samples\.sync\.ex.*}
]
