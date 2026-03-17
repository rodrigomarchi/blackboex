defmodule Blackboex.LLM do
  @moduledoc """
  Public API for LLM operations: usage tracking.
  """

  alias Blackboex.LLM.Usage
  alias Blackboex.Repo

  @spec record_usage(map()) :: {:ok, Usage.t()} | {:error, Ecto.Changeset.t()}
  def record_usage(attrs) do
    %Usage{}
    |> Usage.changeset(attrs)
    |> Repo.insert()
  end
end
