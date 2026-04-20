defmodule Blackboex.AccountsFixtures do
  @moduledoc """
  This module defines test helpers for creating
  entities via the `Blackboex.Accounts` context.
  """

  import Ecto.Query

  alias Blackboex.Accounts
  alias Blackboex.Accounts.Scope

  def unique_user_email do
    # `System.unique_integer/1` only guarantees uniqueness within the current
    # BEAM lifetime. If a prior test process ever leaked a row out of the
    # Ecto sandbox (rare but has happened here), a fresh BEAM will happily
    # regenerate the same integer and collide with the residue. We also mix
    # in a random suffix so every generated email is unique across runs
    # regardless of any residual rows.
    suffix = :crypto.strong_rand_bytes(4) |> Base.url_encode64(padding: false)
    "user#{System.unique_integer([:positive])}-#{suffix}@example.com"
  end

  def valid_user_password, do: "hello world!"

  def valid_user_attributes(attrs \\ %{}) do
    Enum.into(attrs, %{
      email: unique_user_email()
    })
  end

  def unconfirmed_user_fixture(attrs \\ %{}) do
    {:ok, user} =
      attrs
      |> valid_user_attributes()
      |> Accounts.register_user()

    user
  end

  def user_fixture(attrs \\ %{}) do
    {extra_attrs, registration_attrs} = Map.pop(attrs, :is_platform_admin)
    {preferences, registration_attrs} = Map.pop(registration_attrs, :preferences)
    user = unconfirmed_user_fixture(registration_attrs)

    token =
      extract_user_token(fn url ->
        Accounts.deliver_login_instructions(user, url)
      end)

    {:ok, {user, _expired_tokens}} =
      Accounts.login_user_by_magic_link(token)

    user =
      if extra_attrs do
        user
        |> Ecto.Changeset.change(is_platform_admin: extra_attrs)
        |> Blackboex.Repo.update!()
      else
        user
      end

    if preferences do
      user
      |> Ecto.Changeset.change(preferences: preferences)
      |> Blackboex.Repo.update!()
    else
      user
    end
  end

  def user_scope_fixture do
    user = user_fixture()
    user_scope_fixture(user)
  end

  def user_scope_fixture(user) do
    Scope.for_user(user)
  end

  def set_password(user) do
    {:ok, {user, _expired_tokens}} =
      Accounts.update_user_password(user, %{password: valid_user_password()})

    user
  end

  def extract_user_token(fun) do
    {:ok, captured_email} = fun.(&"[TOKEN]#{&1}[TOKEN]")
    [_, token | _] = String.split(captured_email.text_body, "[TOKEN]")
    token
  end

  def override_token_authenticated_at(token, authenticated_at) when is_binary(token) do
    Blackboex.Repo.update_all(
      from(t in Accounts.UserToken,
        where: t.token == ^token
      ),
      set: [authenticated_at: authenticated_at]
    )
  end

  def generate_user_magic_link_token(user) do
    {encoded_token, user_token} = Accounts.UserToken.build_email_token(user, "login")
    Blackboex.Repo.insert!(user_token)
    {encoded_token, user_token.token}
  end

  def offset_user_token(token, amount_to_add, unit) do
    dt = DateTime.add(DateTime.utc_now(), amount_to_add, unit)

    Blackboex.Repo.update_all(
      from(ut in Accounts.UserToken, where: ut.token == ^token),
      set: [inserted_at: dt, authenticated_at: dt]
    )
  end
end
