defmodule Blackboex.Flows.Templates do
  @moduledoc """
  Template library for flows.

  Provides a catalogue of predefined BlackboexFlow definitions that users can
  instantiate to create new flows. Mirrors the `Blackboex.Apis.Templates` pattern.
  """

  @type template :: %{
          id: String.t(),
          name: String.t(),
          description: String.t(),
          category: String.t(),
          icon: String.t(),
          definition: map()
        }

  @category_order [
    "Getting Started"
  ]

  @templates [
    Blackboex.Flows.Templates.HelloWorld.template()
  ]

  @doc "Returns all available flow templates."
  @spec list() :: [template()]
  def list, do: @templates

  @doc "Returns a flow template by its id, or nil if not found."
  @spec get(String.t()) :: template() | nil
  def get(id) do
    Enum.find(@templates, fn t -> t.id == id end)
  end

  @doc "Returns flow templates grouped by category, in canonical order."
  @spec list_by_category() :: [{String.t(), [template()]}]
  def list_by_category do
    grouped = Enum.group_by(@templates, & &1.category)

    @category_order
    |> Enum.filter(&Map.has_key?(grouped, &1))
    |> Enum.map(fn cat -> {cat, Map.fetch!(grouped, cat)} end)
  end
end
