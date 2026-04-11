defmodule BlackboexWeb.UserLive.Confirmation do
  use BlackboexWeb, :live_view

  import BlackboexWeb.Components.UI.AlertBanner

  alias Blackboex.Accounts

  @impl true
  def render(assigns) do
    ~H"""
    <div class="space-y-4">
      <div class="text-center">
        <.header>Welcome {@user.email}</.header>
      </div>

      <.form
        :if={!@user.confirmed_at}
        for={@form}
        id="confirmation_form"
        phx-mounted={JS.focus_first()}
        phx-submit="submit"
        action={~p"/users/log-in?_action=confirmed"}
        phx-trigger-action={@trigger_submit}
      >
        <.input type="hidden" field={@form[:token]} />
        <.button
          name={@form[:remember_me].name}
          value="true"
          phx-disable-with="Confirming..."
          class="w-full"
        >
          <.icon name="hero-shield-check" class="mr-1.5 size-3.5 text-accent-emerald" />
          Confirm and stay logged in
        </.button>
        <.button phx-disable-with="Confirming..." class="w-full mt-2">
          <.icon name="hero-arrow-right-end-on-rectangle" class="mr-1.5 size-3.5 text-accent-sky" />
          Confirm and log in only this time
        </.button>
      </.form>

      <.form
        :if={@user.confirmed_at}
        for={@form}
        id="login_form"
        phx-submit="submit"
        phx-mounted={JS.focus_first()}
        action={~p"/users/log-in"}
        phx-trigger-action={@trigger_submit}
      >
        <.input type="hidden" field={@form[:token]} />
        <%= if @current_scope do %>
          <.button phx-disable-with="Logging in..." class="w-full">
            <.icon name="hero-arrow-right-end-on-rectangle" class="mr-1.5 size-3.5 text-accent-amber" />
            Log in
          </.button>
        <% else %>
          <.button
            name={@form[:remember_me].name}
            value="true"
            phx-disable-with="Logging in..."
            class="w-full"
          >
            <.icon name="hero-device-phone-mobile" class="mr-1.5 size-3.5 text-accent-emerald" />
            Keep me logged in on this device
          </.button>
          <.button phx-disable-with="Logging in..." class="w-full mt-2">
            <.icon name="hero-arrow-right-end-on-rectangle" class="mr-1.5 size-3.5 text-accent-sky" />
            Log me in only this time
          </.button>
        <% end %>
      </.form>

      <.alert_banner :if={!@user.confirmed_at} variant="neutral" class="mt-8">
        Tip: If you prefer passwords, you can enable them in the user settings.
      </.alert_banner>
    </div>
    """
  end

  @impl true
  def mount(%{"token" => token}, _session, socket) do
    if user = Accounts.get_user_by_magic_link_token(token) do
      form = to_form(%{"token" => token}, as: "user")

      {:ok, assign(socket, user: user, form: form, trigger_submit: false),
       temporary_assigns: [form: nil]}
    else
      {:ok,
       socket
       |> put_flash(:error, "Magic link is invalid or it has expired.")
       |> push_navigate(to: ~p"/users/log-in")}
    end
  end

  @impl true
  def handle_event("submit", %{"user" => params}, socket) do
    {:noreply, assign(socket, form: to_form(params, as: "user"), trigger_submit: true)}
  end
end
