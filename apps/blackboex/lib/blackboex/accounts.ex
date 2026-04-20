defmodule Blackboex.Accounts do
  @moduledoc """
  The Accounts context.
  """

  alias Blackboex.Accounts.{User, UserNotifier, UserQueries, UserToken}
  alias Blackboex.Organizations.{Membership, Organization}
  alias Blackboex.Projects.{Project, ProjectMembership}
  alias Blackboex.Repo

  # Whitelisted top-level keys for user preferences. Add new roots here as features require them.
  @preferences_allowed_roots ~w(sidebar_tree)

  ## Database getters

  @doc """
  Gets a user by email.

  ## Examples

      iex> get_user_by_email("foo@example.com")
      %User{}

      iex> get_user_by_email("unknown@example.com")
      nil

  """
  def get_user_by_email(email) when is_binary(email) do
    Repo.get_by(User, email: email)
  end

  @doc """
  Gets a user by email and password.

  ## Examples

      iex> get_user_by_email_and_password("foo@example.com", "correct_password")
      %User{}

      iex> get_user_by_email_and_password("foo@example.com", "invalid_password")
      nil

  """
  def get_user_by_email_and_password(email, password)
      when is_binary(email) and is_binary(password) do
    user = Repo.get_by(User, email: email)
    if User.valid_password?(user, password), do: user
  end

  @doc """
  Gets a single user.

  Returns nil if the User does not exist.

  ## Examples

      iex> get_user(123)
      %User{}

      iex> get_user(456)
      nil

  """
  def get_user(id), do: Repo.get(User, id)

  @doc """
  Gets a single user. Raises if not found.
  Use only in contexts where absence is a programming error, not user input.
  """
  def get_user!(id), do: Repo.get!(User, id)

  @doc """
  Persists the user's last-visited organization and optional project.
  Skips the write when the fields already match, to avoid churn.
  """
  @spec touch_last_visited(User.t(), Ecto.UUID.t() | nil, Ecto.UUID.t() | nil) ::
          {:ok, User.t()} | {:error, Ecto.Changeset.t()}
  def touch_last_visited(%User{} = user, organization_id, project_id) do
    if user.last_organization_id == organization_id and user.last_project_id == project_id do
      {:ok, user}
    else
      user
      |> User.last_visited_changeset(%{
        last_organization_id: organization_id,
        last_project_id: project_id
      })
      |> Repo.update()
    end
  end

  ## User preferences

  @doc """
  Writes a leaf value in the user's `preferences` JSONB blob at the given string-key path.
  The first path segment must be in `@preferences_allowed_roots`; empty or unlisted roots
  return `{:error, :forbidden}`. Missing intermediate keys are created automatically.
  """
  @spec update_user_preference(User.t(), [String.t()], term()) ::
          {:ok, User.t()} | {:error, Ecto.Changeset.t() | :forbidden}
  def update_user_preference(%User{} = user, path, value) do
    with [root | _] <- path,
         true <- root in @preferences_allowed_roots do
      access_path = Enum.map(path, &Access.key(&1, %{}))
      new_prefs = put_in(user.preferences, access_path, value)

      user
      |> User.preferences_changeset(%{preferences: new_prefs})
      |> Repo.update()
    else
      _ -> {:error, :forbidden}
    end
  end

  @doc """
  Reads a value from the user's `preferences` JSONB blob at the given string-key path.
  Returns `default` when the path does not exist or any intermediate key is missing.
  """
  @spec get_user_preference(User.t(), [String.t()], default) :: term() | default
        when default: var
  def get_user_preference(%User{preferences: prefs}, path, default) do
    case Enum.reduce_while(path, prefs, &descend_preferences/2) do
      :__not_found__ -> default
      value -> value
    end
  end

  defp descend_preferences(key, acc) when is_map(acc) do
    case Map.fetch(acc, key) do
      {:ok, val} -> {:cont, val}
      :error -> {:halt, :__not_found__}
    end
  end

  defp descend_preferences(_key, _acc), do: {:halt, :__not_found__}

  ## User registration

  @doc """
  Registers a user.

  ## Examples

      iex> register_user(%{field: value})
      {:ok, %User{}}

      iex> register_user(%{field: bad_value})
      {:error, %Ecto.Changeset{}}

  """
  def register_user(attrs) do
    Ecto.Multi.new()
    |> Ecto.Multi.insert(:user, User.email_changeset(%User{}, attrs))
    |> Ecto.Multi.insert(:organization, fn %{user: user} ->
      Organization.changeset(%Organization{}, %{name: personal_org_name(user.email)})
    end)
    |> Ecto.Multi.insert(:membership, fn %{user: user, organization: org} ->
      Membership.changeset(%Membership{}, %{
        user_id: user.id,
        organization_id: org.id,
        role: :owner
      })
    end)
    |> Ecto.Multi.insert(:project, fn %{organization: org} ->
      Project.changeset(%Project{}, %{
        name: "Default",
        organization_id: org.id
      })
    end)
    |> Ecto.Multi.insert(:project_membership, fn %{project: project, user: user} ->
      ProjectMembership.changeset(
        %ProjectMembership{},
        %{
          project_id: project.id,
          user_id: user.id,
          role: :admin
        }
      )
    end)
    |> Repo.transaction()
    |> case do
      {:ok, %{user: user}} -> {:ok, user}
      {:error, :user, changeset, _} -> {:error, changeset}
      {:error, _step, _changeset, _} -> {:error, :registration_failed}
    end
  end

  defp personal_org_name(email) do
    prefix = email |> String.split("@") |> hd()
    suffix = :crypto.strong_rand_bytes(3) |> Base.url_encode64(padding: false)
    "#{prefix}-#{suffix}"
  end

  ## Settings

  @doc """
  Checks whether the user is in sudo mode.

  The user is in sudo mode when the last authentication was done no further
  than 20 minutes ago. The limit can be given as second argument in minutes.
  """
  def sudo_mode?(user, minutes \\ -20)

  def sudo_mode?(%User{authenticated_at: ts}, minutes) when is_struct(ts, DateTime) do
    DateTime.after?(ts, DateTime.utc_now() |> DateTime.add(minutes, :minute))
  end

  def sudo_mode?(_user, _minutes), do: false

  @doc """
  Returns an `%Ecto.Changeset{}` for changing the user email.

  See `Blackboex.Accounts.User.email_changeset/3` for a list of supported options.

  ## Examples

      iex> change_user_email(user)
      %Ecto.Changeset{data: %User{}}

  """
  def change_user_email(user, attrs \\ %{}, opts \\ []) do
    User.email_changeset(user, attrs, opts)
  end

  @doc """
  Updates the user email using the given token.

  If the token matches, the user email is updated and the token is deleted.
  """
  def update_user_email(user, token) do
    context = "change:#{user.email}"

    Repo.transact(fn ->
      with {:ok, query} <- UserToken.verify_change_email_token_query(token, context),
           %UserToken{sent_to: email} <- Repo.one(query),
           {:ok, user} <- Repo.update(User.email_changeset(user, %{email: email})),
           {_count, _result} <-
             Repo.delete_all(UserQueries.user_tokens_by_context(user.id, context)) do
        {:ok, user}
      else
        _ -> {:error, :transaction_aborted}
      end
    end)
  end

  @doc """
  Returns an `%Ecto.Changeset{}` for changing the user password.

  See `Blackboex.Accounts.User.password_changeset/3` for a list of supported options.

  ## Examples

      iex> change_user_password(user)
      %Ecto.Changeset{data: %User{}}

  """
  def change_user_password(user, attrs \\ %{}, opts \\ []) do
    User.password_changeset(user, attrs, opts)
  end

  @doc """
  Updates the user password.

  Returns a tuple with the updated user, as well as a list of expired tokens.

  ## Examples

      iex> update_user_password(user, %{password: ...})
      {:ok, {%User{}, [...]}}

      iex> update_user_password(user, %{password: "too short"})
      {:error, %Ecto.Changeset{}}

  """
  def update_user_password(user, attrs) do
    user
    |> User.password_changeset(attrs)
    |> update_user_and_delete_all_tokens()
  end

  ## Session

  @doc """
  Generates a session token.
  """
  def generate_user_session_token(user) do
    {token, user_token} = UserToken.build_session_token(user)
    Repo.insert!(user_token)
    token
  end

  @doc """
  Gets the user with the given signed token.

  If the token is valid `{user, token_inserted_at}` is returned, otherwise `nil` is returned.
  """
  def get_user_by_session_token(token) do
    {:ok, query} = UserToken.verify_session_token_query(token)
    Repo.one(query)
  end

  @doc """
  Gets the user with the given magic link token.
  """
  def get_user_by_magic_link_token(token) do
    with {:ok, query} <- UserToken.verify_magic_link_token_query(token),
         {user, _token} <- Repo.one(query) do
      user
    else
      _ -> nil
    end
  end

  @doc """
  Logs the user in by magic link.

  There are three cases to consider:

  1. The user has already confirmed their email. They are logged in
     and the magic link is expired.

  2. The user has not confirmed their email and no password is set.
     In this case, the user gets confirmed, logged in, and all tokens -
     including session ones - are expired. In theory, no other tokens
     exist but we delete all of them for best security practices.

  3. The user has not confirmed their email but a password is set.
     This cannot happen in the default implementation but may be the
     source of security pitfalls. See the "Mixing magic link and password registration" section of
     `mix help phx.gen.auth`.
  """
  def login_user_by_magic_link(token) do
    {:ok, query} = UserToken.verify_magic_link_token_query(token)

    case Repo.one(query) do
      # Prevent session fixation attacks by disallowing magic links for unconfirmed users with password
      {%User{confirmed_at: nil, hashed_password: hash}, _token} when not is_nil(hash) ->
        raise """
        magic link log in is not allowed for unconfirmed users with a password set!

        This cannot happen with the default implementation, which indicates that you
        might have adapted the code to a different use case. Please make sure to read the
        "Mixing magic link and password registration" section of `mix help phx.gen.auth`.
        """

      {%User{confirmed_at: nil} = user, _token} ->
        user
        |> User.confirm_changeset()
        |> update_user_and_delete_all_tokens()

      {user, token} ->
        Repo.delete!(token)
        {:ok, {user, []}}

      nil ->
        {:error, :not_found}
    end
  end

  @doc ~S"""
  Delivers the update email instructions to the given user.

  ## Examples

      iex> deliver_user_update_email_instructions(user, current_email, &url(~p"/users/settings/confirm-email/#{&1}"))
      {:ok, %{to: ..., body: ...}}

  """
  def deliver_user_update_email_instructions(%User{} = user, current_email, update_email_url_fun)
      when is_function(update_email_url_fun, 1) do
    {encoded_token, user_token} = UserToken.build_email_token(user, "change:#{current_email}")

    Repo.insert!(user_token)
    UserNotifier.deliver_update_email_instructions(user, update_email_url_fun.(encoded_token))
  end

  @doc """
  Delivers the magic link login instructions to the given user.
  """
  def deliver_login_instructions(%User{} = user, magic_link_url_fun)
      when is_function(magic_link_url_fun, 1) do
    {encoded_token, user_token} = UserToken.build_email_token(user, "login")
    Repo.insert!(user_token)
    UserNotifier.deliver_login_instructions(user, magic_link_url_fun.(encoded_token))
  end

  @doc """
  Deletes the signed token with the given context.
  """
  def delete_user_session_token(token) do
    token |> UserQueries.session_token() |> Repo.delete_all()
    :ok
  end

  ## Token helper

  defp update_user_and_delete_all_tokens(changeset) do
    Repo.transact(fn ->
      with {:ok, user} <- Repo.update(changeset) do
        tokens_to_expire = Repo.all_by(UserToken, user_id: user.id)

        Repo.delete_all(UserQueries.user_tokens_by_ids(Enum.map(tokens_to_expire, & &1.id)))

        {:ok, {user, tokens_to_expire}}
      end
    end)
  end
end
