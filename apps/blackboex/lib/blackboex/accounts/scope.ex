defmodule Blackboex.Accounts.Scope do
  @moduledoc """
  Defines the scope of the caller to be used throughout the app.

  The `Blackboex.Accounts.Scope` allows public interfaces to receive
  information about the caller, such as if the call is initiated from an
  end-user, and if so, which user. Additionally, such a scope can carry fields
  such as "super user" or other privileges for use as authorization, or to
  ensure specific code paths can only be access for a given scope.

  It is useful for logging as well as for scoping pubsub subscriptions and
  broadcasts when a caller subscribes to an interface or performs a particular
  action.

  Feel free to extend the fields on this struct to fit the needs of
  growing application requirements.
  """

  alias Blackboex.Accounts.User
  alias Blackboex.Organizations.{Membership, Organization}

  @type t :: %__MODULE__{}

  defstruct user: nil, organization: nil, membership: nil

  @doc """
  Creates a scope for the given user.

  Returns nil if no user is given.
  """
  @spec for_user(User.t()) :: t()
  @spec for_user(nil) :: nil
  def for_user(%User{} = user) do
    %__MODULE__{user: user}
  end

  def for_user(nil), do: nil

  @doc """
  Sets the organization and membership on the scope.
  """
  @spec with_organization(t(), Organization.t(), Membership.t()) :: t()
  def with_organization(%__MODULE__{} = scope, %Organization{} = org, %Membership{} = mem) do
    %{scope | organization: org, membership: mem}
  end
end
