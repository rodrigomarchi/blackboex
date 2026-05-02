defmodule Blackboex.Organizations.OrgInvitationNotifier do
  @moduledoc "Sends organization invitation emails."
  import Swoosh.Email

  alias Blackboex.Mailer
  alias Blackboex.Organizations.Invitation
  alias Blackboex.Settings

  @spec deliver_invitation(Invitation.t(), String.t()) ::
          {:ok, Swoosh.Email.t()} | {:error, term()}
  def deliver_invitation(%Invitation{} = invitation, raw_token) when is_binary(raw_token) do
    accept_url = "#{base_url()}/invitations/#{raw_token}"

    body = """
    You have been invited to join an organization on Blackboex.

    Click the link below to accept (link expires #{DateTime.to_iso8601(invitation.expires_at)}):

    #{accept_url}

    If you weren't expecting this invitation, you can ignore this message.
    """

    email =
      new()
      |> to(invitation.email)
      |> from({"Blackboex", "contact@example.com"})
      |> subject("You've been invited to Blackboex")
      |> text_body(body)

    with {:ok, _meta} <- Mailer.deliver(email) do
      {:ok, email}
    end
  end

  defp base_url do
    case Settings.get_settings() do
      %{public_url: url} when is_binary(url) and url != "" -> url
      _ -> "http://localhost:4000"
    end
  end
end
