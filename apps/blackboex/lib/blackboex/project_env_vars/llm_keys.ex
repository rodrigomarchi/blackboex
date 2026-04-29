defmodule Blackboex.ProjectEnvVars.LlmKeys do
  @moduledoc """
  Manages project-scoped LLM integration keys.

  Currently only the Anthropic provider is supported (`kind =
  "llm_anthropic"`, name fixed as `"ANTHROPIC_API_KEY"`). The partial unique
  index on `(project_id, kind) where kind = 'llm_anthropic'` guarantees at
  most one Anthropic key per project.
  """

  alias Blackboex.Audit
  alias Blackboex.ProjectEnvVars.ProjectEnvVar
  alias Blackboex.ProjectEnvVars.ProjectEnvVarQueries
  alias Blackboex.Repo

  @anthropic_kind "llm_anthropic"
  @anthropic_name "ANTHROPIC_API_KEY"

  @type provider :: :anthropic
  @type any_provider :: atom()

  @doc """
  Returns the plaintext LLM key for a provider, or `{:error, :not_configured}`
  when the project hasn't set one up. Unsupported providers return
  `{:error, :provider_not_supported}`.
  """
  @spec get_llm_key(Ecto.UUID.t(), any_provider()) ::
          {:ok, String.t()} | {:error, :not_configured | :provider_not_supported}
  def get_llm_key(project_id, :anthropic) do
    case fetch_anthropic(project_id) do
      nil -> {:error, :not_configured}
      %ProjectEnvVar{} = env_var -> {:ok, env_var.encrypted_value}
    end
  end

  def get_llm_key(_project_id, _other), do: {:error, :provider_not_supported}

  @doc """
  Returns the masked (display-safe) form of the configured LLM key, or
  `{:error, :not_configured}` when none exists.

  Intended for LiveViews / templates — the plaintext never leaves the
  server context this way. Short keys (<12 chars) are fully bulleted;
  longer keys keep the first 6 and last 4 characters.
  """
  @spec get_masked_key(Ecto.UUID.t(), any_provider()) ::
          {:ok, String.t()} | {:error, :not_configured | :provider_not_supported}
  def get_masked_key(project_id, :anthropic) do
    case fetch_anthropic(project_id) do
      nil ->
        {:error, :not_configured}

      %ProjectEnvVar{} = env_var ->
        {:ok, mask_key(env_var.encrypted_value)}
    end
  end

  def get_masked_key(_project_id, _other), do: {:error, :provider_not_supported}

  @spec mask_key(String.t()) :: String.t()
  defp mask_key(key) when is_binary(key) do
    size = byte_size(key)

    cond do
      size == 0 -> ""
      size < 12 -> String.duplicate("•", size)
      true -> String.slice(key, 0, 6) <> "..." <> String.slice(key, size - 4, 4)
    end
  end

  @doc """
  Upserts an LLM key for a provider. Returns the persisted `%ProjectEnvVar{}`
  on success. Rejects empty values and unsupported providers.
  """
  @spec put_llm_key(Ecto.UUID.t(), any_provider(), String.t(), Ecto.UUID.t()) ::
          {:ok, ProjectEnvVar.t()}
          | {:error, Ecto.Changeset.t() | :provider_not_supported}
  def put_llm_key(project_id, :anthropic, value, organization_id) when is_binary(value) do
    attrs = %{
      project_id: project_id,
      organization_id: organization_id,
      name: @anthropic_name,
      kind: @anthropic_kind,
      value: value
    }

    result =
      case fetch_anthropic(project_id) do
        nil ->
          %ProjectEnvVar{}
          |> ProjectEnvVar.changeset(attrs)
          |> Repo.insert()

        %ProjectEnvVar{} = existing ->
          existing
          |> ProjectEnvVar.changeset(attrs)
          |> Repo.update()
      end

    case result do
      {:ok, env_var} = ok ->
        Audit.log_async("project_llm_key.set", %{
          resource_type: "project_env_var",
          resource_id: env_var.id,
          organization_id: env_var.organization_id,
          project_id: env_var.project_id,
          metadata: %{provider: "anthropic"}
        })

        ok

      {:error, _changeset} = error ->
        error
    end
  end

  def put_llm_key(_project_id, _other, _value, _organization_id),
    do: {:error, :provider_not_supported}

  @doc """
  Deletes the LLM key for a provider. Idempotent: returns `:ok` whether or
  not a row existed. Unsupported providers return
  `{:error, :provider_not_supported}`.
  """
  @spec delete_llm_key(Ecto.UUID.t(), any_provider()) ::
          :ok | {:error, :provider_not_supported}
  def delete_llm_key(project_id, :anthropic) do
    case fetch_anthropic(project_id) do
      nil ->
        :ok

      %ProjectEnvVar{} = env_var ->
        do_delete_anthropic(env_var)
    end
  end

  def delete_llm_key(_project_id, _other), do: {:error, :provider_not_supported}

  # Repo.delete can raise `Ecto.StaleEntryError` if the row was removed by a
  # concurrent process between `fetch_anthropic/1` and the delete; we treat
  # the operation as idempotent and just return `:ok` without auditing.
  defp do_delete_anthropic(%ProjectEnvVar{} = env_var) do
    case Repo.delete(env_var) do
      {:ok, deleted} ->
        Audit.log_async("project_llm_key.deleted", %{
          resource_type: "project_env_var",
          resource_id: deleted.id,
          organization_id: deleted.organization_id,
          project_id: deleted.project_id,
          metadata: %{provider: "anthropic"}
        })

        :ok

      {:error, _changeset} ->
        :ok
    end
  rescue
    Ecto.StaleEntryError -> :ok
  end

  defp fetch_anthropic(project_id) do
    project_id
    |> ProjectEnvVarQueries.by_project_and_kind(@anthropic_kind)
    |> Repo.one()
  end
end
