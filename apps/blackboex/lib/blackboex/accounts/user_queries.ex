defmodule Blackboex.Accounts.UserQueries do
  @moduledoc "Composable query builders for User and UserToken schemas."
  import Ecto.Query, warn: false
  alias Blackboex.Accounts.UserToken

  @spec session_token(binary()) :: Ecto.Query.t()
  def session_token(token) do
    from(UserToken, where: [token: ^token, context: "session"])
  end

  @spec user_tokens_by_context(integer(), String.t()) :: Ecto.Query.t()
  def user_tokens_by_context(user_id, context) do
    from(UserToken, where: [user_id: ^user_id, context: ^context])
  end

  @spec user_tokens_by_ids([integer()]) :: Ecto.Query.t()
  def user_tokens_by_ids(token_ids) do
    from(t in UserToken, where: t.id in ^token_ids)
  end
end
