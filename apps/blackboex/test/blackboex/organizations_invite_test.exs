defmodule Blackboex.OrganizationsInviteTest do
  use Blackboex.DataCase, async: false

  import Swoosh.TestAssertions

  alias Blackboex.Accounts
  alias Blackboex.Organizations
  alias Blackboex.Organizations.{Invitation, Membership}
  alias Blackboex.Repo
  alias Ecto.Adapters.SQL.Sandbox

  describe "invite_member/3" do
    setup [:create_user_and_org]

    test "creates an invitation with a hashed token and returns raw_token", %{
      user: user,
      org: org
    } do
      assert {:ok, %{invitation: invitation, raw_token: raw_token}} =
               Organizations.invite_member(org, user, %{email: "new@example.com", role: :member})

      assert %Invitation{} = invitation
      assert invitation.email == "new@example.com"
      assert invitation.role == :member
      assert invitation.organization_id == org.id
      assert invitation.invited_by_id == user.id
      assert is_binary(invitation.token_hash)
      assert is_binary(raw_token)
    end

    test "raw token is at least 43 characters (32 bytes Base64URL)", %{user: user, org: org} do
      {:ok, %{raw_token: raw_token}} =
        Organizations.invite_member(org, user, %{email: "rawtoken@example.com", role: :member})

      assert byte_size(raw_token) >= 43
    end

    test "stored token_hash differs from raw_token and matches SHA-256", %{user: user, org: org} do
      {:ok, %{invitation: invitation, raw_token: raw_token}} =
        Organizations.invite_member(org, user, %{email: "hash@example.com", role: :member})

      assert invitation.token_hash != raw_token
      assert invitation.token_hash == :crypto.hash(:sha256, raw_token)
    end

    test "expires_at is +7 days by default", %{user: user, org: org} do
      before = DateTime.utc_now()

      {:ok, %{invitation: invitation}} =
        Organizations.invite_member(org, user, %{email: "expiry@example.com", role: :member})

      diff_seconds = DateTime.diff(invitation.expires_at, before, :second)
      # ~7 days, allow 5 seconds drift either way
      assert diff_seconds >= 7 * 24 * 60 * 60 - 5
      assert diff_seconds <= 7 * 24 * 60 * 60 + 5
    end

    test "delivers an email containing the raw token in the URL", %{user: user, org: org} do
      # Drain any prior test emails (e.g. magic-link from user fixture).
      drain_swoosh_mailbox()

      {:ok, %{raw_token: raw_token}} =
        Organizations.invite_member(org, user, %{email: "mailme@example.com", role: :member})

      assert_email_sent(fn email ->
        assert {"Blackboex", "contact@example.com"} = email.from
        assert [{_, "mailme@example.com"}] = email.to
        assert String.contains?(email.text_body, raw_token)
      end)
    end

    test "duplicate pending invite to same email returns {:error, changeset}", %{
      user: user,
      org: org
    } do
      {:ok, _} =
        Organizations.invite_member(org, user, %{email: "dup@example.com", role: :member})

      assert {:error, %Ecto.Changeset{} = cs} =
               Organizations.invite_member(org, user, %{email: "dup@example.com", role: :member})

      refute cs.valid?
    end

    test "after the previous invite is accepted, a new invite to the same email is allowed",
         %{user: user, org: org} do
      {:ok, %{raw_token: raw_token}} =
        Organizations.invite_member(org, user, %{email: "reinvite@example.com", role: :member})

      {:ok, _} = Organizations.accept_invitation(raw_token, %{password: "longenoughpassword"})

      assert {:ok, %{invitation: %Invitation{}}} =
               Organizations.invite_member(org, user, %{
                 email: "reinvite@example.com",
                 role: :member
               })
    end
  end

  describe "accept_invitation/2" do
    setup [:create_user_and_org]

    test "creates a brand new user when email is not registered yet, sets password",
         %{user: user, org: org} do
      {:ok, %{raw_token: raw_token}} =
        Organizations.invite_member(org, user, %{email: "newuser@example.com", role: :member})

      assert nil == Accounts.get_user_by_email("newuser@example.com")

      assert {:ok, %{user: new_user}} =
               Organizations.accept_invitation(raw_token, %{password: "longenoughpassword"})

      assert new_user.email == "newuser@example.com"
      assert new_user.confirmed_at != nil
      assert is_binary(new_user.hashed_password)
    end

    test "creates membership for the new user", %{user: user, org: org} do
      {:ok, %{raw_token: raw_token}} =
        Organizations.invite_member(org, user, %{email: "newmember@example.com", role: :admin})

      assert {:ok, %{membership: membership, user: new_user, organization: returned_org}} =
               Organizations.accept_invitation(raw_token, %{password: "longenoughpassword"})

      assert membership.user_id == new_user.id
      assert membership.organization_id == org.id
      assert membership.role == :admin
      assert returned_org.id == org.id
    end

    test "creates membership for an existing user (no new User row)", %{user: user, org: org} do
      existing = user_fixture(%{})

      user_count_before = Repo.aggregate(Blackboex.Accounts.User, :count)

      {:ok, %{raw_token: raw_token}} =
        Organizations.invite_member(org, user, %{email: existing.email, role: :member})

      assert {:ok, %{user: returned_user, membership: membership}} =
               Organizations.accept_invitation(raw_token)

      assert returned_user.id == existing.id
      assert membership.user_id == existing.id

      user_count_after = Repo.aggregate(Blackboex.Accounts.User, :count)
      assert user_count_after == user_count_before
    end

    test "marks accepted_at on success", %{user: user, org: org} do
      {:ok, %{invitation: invitation, raw_token: raw_token}} =
        Organizations.invite_member(org, user, %{email: "accepted@example.com", role: :member})

      assert is_nil(invitation.accepted_at)

      {:ok, _} = Organizations.accept_invitation(raw_token, %{password: "longenoughpassword"})

      reloaded = Repo.get!(Invitation, invitation.id)
      assert %DateTime{} = reloaded.accepted_at
    end

    test "is idempotent: second call with same token returns {:error, :invalid_token}",
         %{user: user, org: org} do
      {:ok, %{raw_token: raw_token}} =
        Organizations.invite_member(org, user, %{email: "idem@example.com", role: :member})

      {:ok, _} = Organizations.accept_invitation(raw_token, %{password: "longenoughpassword"})

      assert {:error, :invalid_token} =
               Organizations.accept_invitation(raw_token, %{password: "longenoughpassword"})
    end

    test "rejects expired token", %{user: user, org: org} do
      {:ok, %{invitation: invitation, raw_token: raw_token}} =
        Organizations.invite_member(org, user, %{email: "expired@example.com", role: :member})

      # Force expiry into the past
      invitation
      |> Ecto.Changeset.change(expires_at: DateTime.add(DateTime.utc_now(), -1, :day))
      |> Repo.update!()

      assert {:error, :invalid_token} =
               Organizations.accept_invitation(raw_token, %{password: "longenoughpassword"})
    end

    test "rejects unknown token" do
      assert {:error, :invalid_token} = Organizations.accept_invitation("totally-bogus-token")
    end

    test "race: two concurrent accepts -> exactly one membership created",
         %{user: user, org: org} do
      {:ok, %{raw_token: raw_token}} =
        Organizations.invite_member(org, user, %{email: "race@example.com", role: :member})

      parent = self()

      # Hand the sandbox to the spawned tasks so they can hit the DB.
      results =
        1..5
        |> Task.async_stream(
          fn _ ->
            Sandbox.allow(Repo, parent, self())
            Organizations.accept_invitation(raw_token, %{password: "longenoughpassword"})
          end,
          max_concurrency: 5,
          ordered: false
        )
        |> Enum.map(fn {:ok, res} -> res end)

      successes = Enum.count(results, &match?({:ok, _}, &1))
      assert successes == 1

      # Exactly one membership for the invited email.
      [user_record] =
        Repo.all(from u in Blackboex.Accounts.User, where: u.email == "race@example.com")

      memberships =
        Repo.all(
          from m in Membership,
            where: m.user_id == ^user_record.id and m.organization_id == ^org.id
        )

      assert length(memberships) == 1
    end
  end

  # Drains any pending Swoosh test emails from the current process mailbox.
  defp drain_swoosh_mailbox do
    receive do
      {:email, _email} -> drain_swoosh_mailbox()
    after
      0 -> :ok
    end
  end
end
