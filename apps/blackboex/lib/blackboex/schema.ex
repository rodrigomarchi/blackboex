defmodule Blackboex.Schema do
  @moduledoc """
  Convenience wrapper for Ecto embedded_schema used in API handler DTOs.

  Replaces the boilerplate of `use Ecto.Schema`, `import Ecto.Changeset`,
  and `@primary_key false` with a single `use Blackboex.Schema`.

  ## Example

      defmodule Request do
        use Blackboex.Schema

        embedded_schema do
          field :number, :integer
        end

        def changeset(params) do
          %__MODULE__{}
          |> cast(params, [:number])
          |> validate_required([:number])
        end
      end
  """

  @spec __using__(keyword()) :: Macro.t()
  defmacro __using__(_opts) do
    quote do
      use Ecto.Schema
      import Ecto.Changeset
      @primary_key false
    end
  end
end
