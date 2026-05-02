defmodule Blackboex.Flows.Templates do
  @moduledoc """
  Template library for flows.

  Provides a catalogue of predefined BlackboexFlow definitions that users can
  instantiate to create new flows. Mirrors the `Blackboex.Apis.Templates` pattern.
  """

  alias Blackboex.Samples.Manifest

  @type template :: %{
          id: String.t(),
          name: String.t(),
          description: String.t(),
          category: String.t(),
          icon: String.t(),
          definition: map()
        }

  @category_order [
    "Getting Started",
    "Data Processing",
    "Integrations",
    "Advanced",
    "AI & LLM",
    "Customer Support",
    "Business Operations",
    "Data & Enrichment",
    "DevOps & Monitoring",
    "Customer Success",
    "API Infrastructure",
    "E-commerce"
  ]

  @doc "Returns all available flow templates."
  @spec list() :: [template()]
  def list, do: Manifest.list_by_kind(:flow)

  @doc "Returns a flow template by its id, or nil if not found."
  @spec get(String.t()) :: template() | nil
  def get(id) do
    Manifest.get_by_kind_and_id(:flow, id)
  end

  @doc "Returns flow templates grouped by category, in canonical order."
  @spec list_by_category() :: [{String.t(), [template()]}]
  def list_by_category do
    grouped = Enum.group_by(list(), & &1.category)

    @category_order
    |> Enum.filter(&Map.has_key?(grouped, &1))
    |> Enum.map(fn cat -> {cat, Map.fetch!(grouped, cat)} end)
  end
end
