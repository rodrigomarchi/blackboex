defmodule BlackboexWeb.InvitationLive.Accept do
  @moduledoc """
  Accept-invitation flow. Mounts an org invitation by raw token, lets
  the invitee set a password (when they're a new user), and on submit
  hands off to `BlackboexWeb.SetupController.finish/2` via a one-time
  `SetupTokens` ETS token to perform the session login.

  Mount raises `Phoenix.Router.NoRouteError` for unknown / expired /
  already-accepted tokens.
  """
  use BlackboexWeb, :live_view

  import BlackboexWeb.Components.Card
  import BlackboexWeb.Components.UI.AlertBanner

  alias Blackboex.Organizations
  alias Blackboex.Organizations.Invitation
  alias BlackboexWeb.SetupTokens

  @impl true
  def mount(%{"token" => raw_token}, _session, socket) do
    case Organizations.find_pending_invitation(raw_token) do
      nil ->
        {:ok,
         socket
         |> put_flash(:error, "This invitation is invalid or expired.")
         |> redirect(to: ~p"/users/log-in")}

      %Invitation{} = invitation ->
        {:ok,
         socket
         |> assign(:invitation, invitation)
         |> assign(:raw_token, raw_token)
         |> assign(:error, nil)
         |> assign(:form, build_form(%{}))}
    end
  end

  @impl true
  def render(assigns) do
    ~H"""
    <div class="space-y-4">
      <div class="text-center">
        <.header>
          You're invited
          <:subtitle>
            Join {@invitation.organization.name} as {@invitation.email}
          </:subtitle>
        </.header>
      </div>

      <.alert_banner :if={@error} variant="destructive" icon="hero-exclamation-circle">
        {@error}
      </.alert_banner>

      <.card>
        <div class="p-6 space-y-4">
          <.form for={@form} id="accept-form" phx-submit="accept">
            <.input
              field={@form[:password]}
              type="password"
              label="Password (min 12 chars)"
              autocomplete="new-password"
              required
            />
            <.input
              field={@form[:password_confirmation]}
              type="password"
              label="Confirm password"
              autocomplete="new-password"
              required
            />
            <.button type="submit" class="w-full">Accept invitation</.button>
          </.form>
        </div>
      </.card>
    </div>
    """
  end

  @impl true
  def handle_event("accept", %{"user" => params}, socket) do
    password = params["password"] || ""
    confirmation = params["password_confirmation"] || ""

    cond do
      password != confirmation ->
        {:noreply,
         socket
         |> assign(:error, "Passwords do not match")
         |> assign(:form, build_form(params))}

      byte_size(password) < 12 ->
        {:noreply,
         socket
         |> assign(:error, "Password must be at least 12 characters")
         |> assign(:form, build_form(params))}

      true ->
        do_accept(socket, password)
    end
  end

  defp do_accept(socket, password) do
    case Organizations.accept_invitation(socket.assigns.raw_token, %{password: password}) do
      {:ok, %{user: user}} ->
        token = SetupTokens.issue(user.id)
        {:noreply, redirect(socket, to: ~p"/setup/finish?token=#{token}")}

      {:error, :invalid_token} ->
        {:noreply, assign(socket, :error, "This invitation is no longer valid.")}

      {:error, _other} ->
        {:noreply, assign(socket, :error, "Could not complete acceptance. Please try again.")}
    end
  end

  defp build_form(params) do
    types = %{password: :string, password_confirmation: :string}

    {%{}, types}
    |> Ecto.Changeset.cast(params, Map.keys(types))
    |> Map.put(:action, nil)
    |> to_form(as: :user)
  end
end
