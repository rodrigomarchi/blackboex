defmodule BlackboexWeb.ProjectLive.LlmIntegrations do
  @moduledoc """
  Project-scoped LiveView for configuring LLM integration keys.

  Currently supports a single provider — Anthropic. The key is stored in
  `project_env_vars` with `kind = "llm_anthropic"`; it is never echoed back
  in plaintext after save (masked as `sk-...XXXX`).

  Actions:
    * Save/update key (upsert via `ProjectEnvVars.put_llm_key/4`)
    * Remove key (`ProjectEnvVars.delete_llm_key/2`)
    * Test connection — a short `generate_text` ping through the resolved
      `Blackboex.LLM.Config.client_for_project/1` to surface
      `:invalid_api_key`, `:rate_limited` or generic errors to the user.
  """
  use BlackboexWeb, :live_view

  alias Blackboex.LLM.Config, as: LLMConfig
  alias Blackboex.ProjectEnvVars

  import BlackboexWeb.Components.Shared.ProjectSettingsTabs

  # Rate-limit parameters (per-project):
  #   - test_connection: 5 req/min (probe attempts)
  #   - save/delete key: 20 req/min (normal admin editing)
  @rate_window_ms 60_000
  @test_limit 5
  @write_limit 20

  @impl true
  def mount(_params, _session, socket) do
    scope = socket.assigns.current_scope
    org = scope.organization
    project = scope.project

    {configured?, masked_key} = load_masked_key(project)

    {:ok,
     socket
     |> assign(:page_title, "LLM Integrations")
     |> assign(:org, org)
     |> assign(:project, project)
     |> assign(:key_configured?, configured?)
     |> assign(:key_masked, masked_key)
     |> assign(:form, to_form(%{"value" => ""}, as: :llm))
     |> assign(:test_state, :idle)
     |> assign(:test_message, nil)}
  end

  @impl true
  def render(assigns) do
    ~H"""
    <.page_header icon="hero-cpu-chip" icon_class="text-accent-violet" title="LLM Integrations" />
    <.page>
      <.project_settings_tabs
        :if={@project}
        active={:llm_integrations}
        org_slug={@org.slug}
        project_slug={@project.slug}
      />

      <div class="max-w-xl space-y-4">
        <h2 class="text-lg font-semibold">Anthropic</h2>

        <%= if @key_configured? do %>
          <div class="rounded-lg border bg-card p-4 space-y-3" data-role="anthropic-configured">
            <p class="text-sm">
              Status: <span class="font-medium text-emerald-700">Configured</span>
            </p>
            <p class="font-mono text-xs" data-role="masked-key">
              {@key_masked}
            </p>
            <div class="flex flex-wrap gap-2">
              <.button
                type="button"
                variant="outline"
                size="sm"
                phx-click="test_connection"
                data-role="test-connection"
              >
                <.icon name="hero-bolt" class="mr-1.5 size-3.5 text-accent-amber" /> Test Connection
              </.button>
              <.button
                type="button"
                variant="destructive"
                size="sm"
                phx-click="delete_key"
                data-confirm="Remove the Anthropic key for this project?"
                data-role="remove-key"
              >
                <.icon name="hero-trash" class="mr-1.5 size-3.5" /> Remove
              </.button>
            </div>

            <div :if={@test_message} class="text-sm" data-role="test-result">
              <span class={test_class(@test_state)}>{@test_message}</span>
            </div>
          </div>

          <div class="rounded-lg border bg-muted p-4 space-y-3">
            <p class="text-sm font-medium">Update key</p>
            <.form
              :let={f}
              for={@form}
              phx-submit="save_key"
              id="update-anthropic-key-form"
              class="space-y-3"
            >
              <.input field={f[:value]} type="text" label="New Anthropic API key" required />
              <.button type="submit" variant="primary" size="sm">
                <.icon name="hero-check" class="mr-1.5 size-3.5" /> Update
              </.button>
            </.form>
          </div>
        <% else %>
          <div
            class="rounded-lg border bg-amber-50 border-amber-300 p-4 space-y-3"
            data-role="anthropic-not-configured"
          >
            <p class="text-sm">
              Status: <span class="font-medium text-amber-800">Not configured</span>
            </p>
            <p class="text-xs text-amber-900">
              AI assist (chat, code generation, and explain) is disabled until you add the
              key. The key is stored per project.
            </p>
          </div>

          <.form
            :let={f}
            for={@form}
            phx-submit="save_key"
            id="create-anthropic-key-form"
            class="space-y-3"
          >
            <.input
              field={f[:value]}
              type="text"
              label="Anthropic API key"
              placeholder="sk-ant-..."
              required
            />
            <.button type="submit" variant="primary" size="sm" data-role="save-key">
              <.icon name="hero-check" class="mr-1.5 size-3.5" /> Save
            </.button>
          </.form>
        <% end %>
      </div>
    </.page>
    """
  end

  @impl true
  def handle_event("save_key", %{"llm" => %{"value" => value}}, socket) do
    value = String.trim(value || "")
    project = socket.assigns.project

    cond do
      value == "" ->
        {:noreply, put_flash(socket, :error, "Key can't be blank")}

      rate_limited?("llm_write", project.id, @write_limit) ->
        {:noreply, put_flash(socket, :error, rate_limit_message())}

      true ->
        do_save_key(socket, value)
    end
  end

  @impl true
  def handle_event("delete_key", _params, socket) do
    project = socket.assigns.project

    if rate_limited?("llm_write", project.id, @write_limit) do
      {:noreply, put_flash(socket, :error, rate_limit_message())}
    else
      do_delete_key(socket, project)
    end
  end

  @impl true
  def handle_event("test_connection", _params, socket) do
    project = socket.assigns.project

    if rate_limited?("llm_test", project.id, @test_limit) do
      {:noreply,
       socket
       |> assign(:test_state, :error)
       |> assign(:test_message, rate_limit_message())}
    else
      do_test_connection(socket, project)
    end
  end

  # ── Private ──────────────────────────────────────────────────────────────

  defp do_delete_key(socket, project) do
    case ProjectEnvVars.delete_llm_key(project.id, :anthropic) do
      :ok ->
        {:noreply,
         socket
         |> assign(:key_configured?, false)
         |> assign(:key_masked, nil)
         |> assign(:test_state, :idle)
         |> assign(:test_message, nil)
         |> assign(:form, to_form(%{"value" => ""}, as: :llm))
         |> put_flash(:info, "Anthropic key removed")}

      {:error, _reason} ->
        {:noreply, put_flash(socket, :error, "Failed to remove key")}
    end
  end

  defp do_test_connection(socket, project) do
    {state, message} =
      case LLMConfig.client_for_project(project.id) do
        {:ok, client, opts} ->
          probe_connection(client, opts)

        {:error, :not_configured} ->
          {:error, "Configure a key first."}
      end

    {:noreply,
     socket
     |> assign(:test_state, state)
     |> assign(:test_message, message)}
  end

  defp do_save_key(socket, value) do
    scope = socket.assigns.current_scope
    project = scope.project
    org = scope.organization

    case ProjectEnvVars.put_llm_key(project.id, :anthropic, value, org.id) do
      {:ok, _env_var} ->
        # NEVER assign plaintext. Re-read masked form server-side.
        {_configured?, masked} = load_masked_key(project)

        {:noreply,
         socket
         |> assign(:key_configured?, true)
         |> assign(:key_masked, masked)
         |> assign(:test_state, :idle)
         |> assign(:test_message, nil)
         |> assign(:form, to_form(%{"value" => ""}, as: :llm))
         |> put_flash(:info, "Anthropic key saved")}

      {:error, %Ecto.Changeset{} = changeset} ->
        errors = changeset_errors(changeset)

        {:noreply,
         socket
         |> assign(:form, to_form(changeset, as: :llm))
         |> put_flash(:error, "Please fix: #{errors}")}

      {:error, :provider_not_supported} ->
        {:noreply, put_flash(socket, :error, "Provider not supported")}
    end
  end

  # Returns `{configured?, masked_key}` for the current project.
  # The plaintext key never leaves the ProjectEnvVars context.
  @spec load_masked_key(struct() | nil) :: {boolean(), String.t() | nil}
  defp load_masked_key(nil), do: {false, nil}

  defp load_masked_key(project) do
    case ProjectEnvVars.get_masked_key(project.id, :anthropic) do
      {:ok, masked} -> {true, masked}
      {:error, _} -> {false, nil}
    end
  end

  defp probe_connection(client, opts) do
    case client.generate_text("ping", Keyword.merge(opts, max_tokens: 1)) do
      {:ok, _response} ->
        {:ok, "Connection OK"}

      {:error, :invalid_api_key} ->
        {:error, "Invalid key"}

      {:error, :rate_limited} ->
        {:error, "Rate limited — try again in a moment."}

      {:error, _other} ->
        {:error, "Network error"}
    end
  end

  defp test_class(:ok), do: "text-emerald-700"
  defp test_class(:error), do: "text-red-600"
  defp test_class(_), do: "text-muted-foreground"

  defp changeset_errors(%Ecto.Changeset{} = cs) do
    cs
    |> Ecto.Changeset.traverse_errors(fn {msg, _} -> msg end)
    |> Enum.map_join("; ", fn {field, msgs} -> "#{field} #{Enum.join(msgs, ", ")}" end)
  end

  # Project-scoped rate limiter buckets for integration admin actions.
  # `bucket_prefix` distinguishes action classes (e.g. "llm_write", "llm_test").
  @spec rate_limited?(String.t(), Ecto.UUID.t(), pos_integer()) :: boolean()
  defp rate_limited?(bucket_prefix, project_id, limit) do
    bucket = "#{bucket_prefix}:#{project_id}"

    case ExRated.check_rate(bucket, @rate_window_ms, limit) do
      {:ok, _count} -> false
      {:error, _limit} -> true
    end
  end

  @spec rate_limit_message() :: String.t()
  defp rate_limit_message, do: "Too many requests — try again in a moment."
end
