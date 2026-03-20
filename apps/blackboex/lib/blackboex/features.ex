defmodule Blackboex.Features do
  @moduledoc """
  Thin wrapper around FunWithFlags for feature flag management.
  """

  alias Blackboex.Accounts.User

  @spec enabled?(atom(), User.t() | nil) :: boolean()
  def enabled?(flag_name, %User{} = user) do
    FunWithFlags.enabled?(flag_name, for: user)
  end

  def enabled?(flag_name, nil) do
    FunWithFlags.enabled?(flag_name)
  end

  @spec enable(atom(), keyword()) :: {:ok, true} | {:error, term()}
  def enable(flag_name, opts \\ []) do
    FunWithFlags.enable(flag_name, opts)
  end

  @spec disable(atom(), keyword()) :: {:ok, false} | {:error, term()}
  def disable(flag_name, opts \\ []) do
    FunWithFlags.disable(flag_name, opts)
  end
end
