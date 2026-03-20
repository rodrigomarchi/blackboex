defimpl FunWithFlags.Actor, for: Blackboex.Accounts.User do
  @spec id(Blackboex.Accounts.User.t()) :: String.t()
  def id(%{id: id}), do: "user:#{id}"
end
