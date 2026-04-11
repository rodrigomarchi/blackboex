defmodule BlackboexWeb.UserLive.Login do
  use BlackboexWeb, :live_view

  alias Blackboex.Accounts

  @impl true
  def render(assigns) do
    ~H"""
    <div class="space-y-4">
      <div class="text-center">
        <.header>
          <p>Log in</p>
          <:subtitle>
            <%= if @current_scope do %>
              You need to reauthenticate to perform sensitive actions on your account.
            <% else %>
              Don't have an account? <.link
                navigate={~p"/users/register"}
                class="font-semibold text-brand hover:underline"
                phx-no-format
              >Sign up</.link> for an account now.
            <% end %>
          </:subtitle>
        </.header>
      </div>

      <div
        :if={local_mail_adapter?()}
        class="flex items-center gap-3 rounded-lg border border-info bg-info/10 p-4 text-info-foreground text-sm"
      >
        <.icon name="hero-information-circle" class="size-5 shrink-0" />
        <div>
          <p>Local mail adapter active.</p>
          <p>
            Visit <.link href="/dev/mailbox" class="underline">the mailbox</.link> for emails.
          </p>
        </div>
      </div>

      <.form
        :let={f}
        for={@form}
        id="login_form_password"
        action={~p"/users/log-in"}
        phx-submit="submit_password"
        phx-trigger-action={@trigger_submit}
      >
        <.input
          readonly={!!@current_scope}
          field={f[:email]}
          type="email"
          label="Email"
          autocomplete="username"
          spellcheck="false"
          required
          phx-mounted={JS.focus()}
        />
        <.input
          field={@form[:password]}
          type="password"
          label="Password"
          autocomplete="current-password"
          spellcheck="false"
        />
        <.button class="w-full" name={@form[:remember_me].name} value="true">
          <.icon name="hero-arrow-right-end-on-rectangle" class="mr-1.5 size-3.5 text-accent-amber" />
          Log in <span aria-hidden="true">&rarr;</span>
        </.button>
      </.form>

      <div class="relative my-4 flex items-center">
        <div class="flex-grow border-t border-border"></div>
        <span class="mx-3 text-muted-caption">or</span>
        <div class="flex-grow border-t border-border"></div>
      </div>

      <.form
        :let={f}
        for={@form}
        id="login_form_magic"
        action={~p"/users/log-in"}
        phx-submit="submit_magic"
      >
        <.input
          readonly={!!@current_scope}
          field={f[:email]}
          type="email"
          label="Email"
          autocomplete="username"
          spellcheck="false"
          required
        />
        <.button class="w-full">
          <.icon name="hero-paper-airplane" class="mr-1.5 size-3.5 text-accent-violet" />
          Send magic link
        </.button>
      </.form>
    </div>
    """
  end

  @impl true
  def mount(_params, _session, socket) do
    email =
      Phoenix.Flash.get(socket.assigns.flash, :email) ||
        get_in(socket.assigns, [:current_scope, Access.key(:user), Access.key(:email)])

    form = to_form(%{"email" => email}, as: "user")

    {:ok, assign(socket, form: form, trigger_submit: false)}
  end

  @impl true
  def handle_event("submit_password", _params, socket) do
    {:noreply, assign(socket, :trigger_submit, true)}
  end

  def handle_event("submit_magic", %{"user" => %{"email" => email}}, socket) do
    if user = Accounts.get_user_by_email(email) do
      Accounts.deliver_login_instructions(
        user,
        &url(~p"/users/log-in/#{&1}")
      )
    end

    info =
      "If your email is in our system, you will receive instructions for logging in shortly."

    {:noreply,
     socket
     |> put_flash(:info, info)
     |> push_navigate(to: ~p"/users/log-in")}
  end

  defp local_mail_adapter? do
    Application.get_env(:blackboex_web, Blackboex.Mailer)[:adapter] == Swoosh.Adapters.Local
  end
end
