defmodule BlackboexWeb.SetupLive do
  @moduledoc """
  First-run setup wizard. Composes only existing design-system
  components: `<.header>`, `<.card>`, `<.section_heading>`,
  `<.input>` (form_field), `<.button>`, `<.alert_banner>`,
  `<.separator>`. Layout is `BlackboexWeb.Layouts, :auth`.

  When `Blackboex.Settings.setup_completed?/0` is `true`, mount
  raises `Phoenix.Router.NoRouteError` (defense in depth — the
  `RequireSetup` plug already 404s `/setup` in that state).

  Submission delegates to `Blackboex.Onboarding.complete_first_run/1`
  and, on success, redirects to `/setup/finish?token=...`, where
  `BlackboexWeb.SetupController` consumes the one-time ETS token
  and logs the user in.
  """
  use BlackboexWeb, :live_view

  import BlackboexWeb.Components.Card
  import BlackboexWeb.Components.Separator
  import BlackboexWeb.Components.UI.AlertBanner
  import BlackboexWeb.Components.UI.SectionHeading

  alias Blackboex.Onboarding
  alias Blackboex.Settings
  alias BlackboexWeb.SetupTokens

  @steps [:instance, :admin, :organization, :review]

  @types %{
    instance: %{app_name: :string, public_url: :string},
    admin: %{
      email: :string,
      password: :string,
      password_confirmation: :string
    },
    organization: %{org_name: :string}
  }

  @impl true
  def mount(_params, _session, socket) do
    if Settings.setup_completed?() do
      raise Phoenix.Router.NoRouteError,
        conn: %Plug.Conn{request_path: "/setup", method: "GET"},
        router: BlackboexWeb.Router
    end

    {:ok,
     socket
     |> assign(step: :instance, data: %{}, error: nil)
     |> assign(:form, build_form(:instance, %{}))}
  end

  @impl true
  def render(assigns) do
    ~H"""
    <div class="space-y-4">
      <div class="text-center">
        <.header>
          First-run setup
          <:subtitle>{subtitle_for(@step)}</:subtitle>
        </.header>
      </div>

      <.alert_banner :if={@error} variant="destructive" icon="hero-exclamation-circle">
        {@error}
      </.alert_banner>

      <.card>
        <div class="p-6 space-y-4">
          <%= case @step do %>
            <% :instance -> %>
              <.section_heading>Instance</.section_heading>
              <.form
                :let={f}
                for={@form}
                id="setup-instance"
                phx-submit="next"
                phx-change="validate"
                as={:setup}
              >
                <.input field={f[:app_name]} type="text" label="App name" required />
                <.input
                  field={f[:public_url]}
                  type="text"
                  label="Public URL"
                  required
                  placeholder="http://localhost:4000"
                />
                <.button type="submit" class="w-full">Next</.button>
              </.form>
            <% :admin -> %>
              <.section_heading>Admin user</.section_heading>
              <.form
                :let={f}
                for={@form}
                id="setup-admin"
                phx-submit="next"
                phx-change="validate"
                as={:setup}
              >
                <.input
                  field={f[:email]}
                  type="email"
                  label="Admin email"
                  autocomplete="username"
                  required
                />
                <.input
                  field={f[:password]}
                  type="password"
                  label="Password (min 12 chars)"
                  autocomplete="new-password"
                  required
                />
                <.input
                  field={f[:password_confirmation]}
                  type="password"
                  label="Confirm password"
                  autocomplete="new-password"
                  required
                />
                <div class="flex gap-2">
                  <.button type="button" phx-click="back" variant="secondary">Back</.button>
                  <.button type="submit" class="flex-1">Next</.button>
                </div>
              </.form>
            <% :organization -> %>
              <.section_heading>Organization</.section_heading>
              <.form
                :let={f}
                for={@form}
                id="setup-org"
                phx-submit="next"
                phx-change="validate"
                as={:setup}
              >
                <.input field={f[:org_name]} type="text" label="Organization name" required />
                <div class="flex gap-2">
                  <.button type="button" phx-click="back" variant="secondary">Back</.button>
                  <.button type="submit" class="flex-1">Next</.button>
                </div>
              </.form>
            <% :review -> %>
              <.section_heading>Review</.section_heading>
              <dl class="space-y-2 text-sm">
                <div>
                  <dt class="font-semibold inline">App:</dt>
                  <dd class="inline">{@data[:app_name]}</dd>
                </div>
                <div>
                  <dt class="font-semibold inline">URL:</dt>
                  <dd class="inline">{@data[:public_url]}</dd>
                </div>
                <div>
                  <dt class="font-semibold inline">Admin:</dt>
                  <dd class="inline">{@data[:email]}</dd>
                </div>
                <div>
                  <dt class="font-semibold inline">Organization:</dt>
                  <dd class="inline">{@data[:org_name]} / Examples</dd>
                </div>
              </dl>
              <.separator class="my-4" />
              <div class="flex gap-2">
                <.button type="button" phx-click="back" variant="secondary">Back</.button>
                <.button type="button" phx-click="complete" class="flex-1">Complete setup</.button>
              </div>
          <% end %>
        </div>
      </.card>
    </div>
    """
  end

  @impl true
  def handle_event("validate", %{"setup" => params}, socket) do
    {:noreply, assign(socket, :form, build_form(socket.assigns.step, params))}
  end

  def handle_event("next", %{"setup" => params}, socket) do
    case validate_step(socket.assigns.step, params) do
      {:ok, valid} ->
        merged = Map.merge(socket.assigns.data, valid)
        next = next_step(socket.assigns.step)

        {:noreply,
         socket
         |> assign(step: next, data: merged, error: nil)
         |> assign(:form, build_form(next, Map.new(merged, fn {k, v} -> {to_string(k), v} end)))}

      {:error, changeset} ->
        {:noreply, assign(socket, :form, to_form(changeset, as: :setup))}
    end
  end

  def handle_event("back", _params, socket) do
    prev = prev_step(socket.assigns.step)
    data = socket.assigns.data

    {:noreply,
     socket
     |> assign(step: prev, error: nil)
     |> assign(:form, build_form(prev, Map.new(data, fn {k, v} -> {to_string(k), v} end)))}
  end

  def handle_event("complete", _params, socket) do
    case Onboarding.complete_first_run(socket.assigns.data) do
      {:ok, %{user: user}} ->
        token = SetupTokens.issue(user.id)
        {:noreply, redirect(socket, to: ~p"/setup/finish?token=#{token}")}

      {:error, :already_completed} ->
        {:noreply,
         socket
         |> assign(:error, "Setup has already been completed.")
         |> redirect(to: ~p"/users/log-in")}

      {:error, %Ecto.Changeset{} = cs} ->
        {:noreply, assign(socket, :error, format_errors(cs))}
    end
  end

  ## Helpers

  defp subtitle_for(:instance), do: "Configure your instance"
  defp subtitle_for(:admin), do: "Create the platform admin"
  defp subtitle_for(:organization), do: "Create the first organization"
  defp subtitle_for(:review), do: "Review and confirm"

  defp next_step(step) do
    idx = Enum.find_index(@steps, &(&1 == step)) || 0
    Enum.at(@steps, min(idx + 1, length(@steps) - 1))
  end

  defp prev_step(step) do
    idx = Enum.find_index(@steps, &(&1 == step)) || 0
    Enum.at(@steps, max(idx - 1, 0))
  end

  defp build_form(step, params) when step in [:instance, :admin, :organization] do
    step
    |> step_changeset(params)
    |> Map.put(:action, nil)
    |> to_form(as: :setup)
  end

  defp build_form(:review, _params), do: to_form(%{}, as: :setup)

  defp step_changeset(:instance, params) do
    {%{}, @types[:instance]}
    |> Ecto.Changeset.cast(params, Map.keys(@types[:instance]))
    |> Ecto.Changeset.validate_required([:app_name, :public_url])
    |> Ecto.Changeset.validate_format(:public_url, ~r{^https?://},
      message: "must be a valid http(s) URL"
    )
  end

  defp step_changeset(:admin, params) do
    {%{}, @types[:admin]}
    |> Ecto.Changeset.cast(params, Map.keys(@types[:admin]))
    |> Ecto.Changeset.validate_required([:email, :password, :password_confirmation])
    |> Ecto.Changeset.validate_format(:email, ~r/^[^@,;\s]+@[^@,;\s]+$/,
      message: "must have the @ sign and no spaces"
    )
    |> Ecto.Changeset.validate_length(:password, min: 12, max: 72)
    |> validate_confirmation()
  end

  defp step_changeset(:organization, params) do
    {%{}, @types[:organization]}
    |> Ecto.Changeset.cast(params, Map.keys(@types[:organization]))
    |> Ecto.Changeset.validate_required([:org_name])
  end

  defp validate_confirmation(changeset) do
    pwd = Ecto.Changeset.get_field(changeset, :password)
    confirmation = Ecto.Changeset.get_field(changeset, :password_confirmation)

    if pwd && confirmation && pwd != confirmation do
      Ecto.Changeset.add_error(changeset, :password_confirmation, "does not match password")
    else
      changeset
    end
  end

  defp validate_step(step, params) do
    cs = step_changeset(step, params)

    if cs.valid? do
      {:ok, drop_confirmation(Ecto.Changeset.apply_changes(cs))}
    else
      {:error, %{cs | action: :validate}}
    end
  end

  defp drop_confirmation(map) when is_map(map), do: Map.delete(map, :password_confirmation)

  defp format_errors(%Ecto.Changeset{errors: errors}) do
    errors
    |> Enum.map(fn {field, {msg, _}} -> "#{field}: #{msg}" end)
    |> Enum.join(", ")
  end
end
