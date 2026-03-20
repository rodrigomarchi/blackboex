defimpl FunWithFlags.Group, for: Blackboex.Accounts.User do
  alias Blackboex.Organizations

  @spec in?(Blackboex.Accounts.User.t(), atom() | String.t()) :: boolean()
  def in?(user, group) when group in [:pro, "pro"] do
    Organizations.get_user_primary_plan(user) in [:pro, :enterprise]
  end

  def in?(user, group) when group in [:enterprise, "enterprise"] do
    Organizations.get_user_primary_plan(user) == :enterprise
  end

  def in?(_user, _group), do: false
end
