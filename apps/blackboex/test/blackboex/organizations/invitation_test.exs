defmodule Blackboex.Organizations.InvitationTest do
  use Blackboex.DataCase, async: true

  alias Blackboex.Organizations.Invitation

  describe "changeset/2" do
    setup do
      {user, org} = user_and_org_fixture()
      token_hash = :crypto.hash(:sha256, "raw-token")

      attrs = %{
        organization_id: org.id,
        email: "invitee@example.com",
        role: :member,
        token_hash: token_hash,
        invited_by_id: user.id,
        expires_at: DateTime.add(DateTime.utc_now(), 7, :day)
      }

      %{attrs: attrs, user: user, org: org}
    end

    test "valid with required attrs", %{attrs: attrs} do
      cs = Invitation.changeset(%Invitation{}, attrs)
      assert cs.valid?
    end

    test "requires email", %{attrs: attrs} do
      cs = Invitation.changeset(%Invitation{}, Map.delete(attrs, :email))
      refute cs.valid?
      assert "can't be blank" in errors_on(cs).email
    end

    test "validates email format", %{attrs: attrs} do
      cs = Invitation.changeset(%Invitation{}, %{attrs | email: "not-an-email"})
      refute cs.valid?
      assert "must be a valid email" in errors_on(cs).email
    end

    test "downcases and trims email", %{attrs: attrs} do
      cs = Invitation.changeset(%Invitation{}, %{attrs | email: "  Invitee@Example.COM "})
      assert cs.valid?
      assert Ecto.Changeset.get_field(cs, :email) == "invitee@example.com"
    end

    test "requires role (rejects explicit nil)", %{attrs: attrs} do
      cs = Invitation.changeset(%Invitation{}, %{attrs | role: nil})
      refute cs.valid?
      assert "can't be blank" in errors_on(cs).role
    end

    test "rejects roles other than :admin and :member", %{attrs: attrs} do
      cs = Invitation.changeset(%Invitation{}, %{attrs | role: :owner})
      refute cs.valid?
      assert errors_on(cs).role |> Enum.any?(&String.contains?(&1, "is invalid"))
    end

    test "accepts :admin", %{attrs: attrs} do
      cs = Invitation.changeset(%Invitation{}, %{attrs | role: :admin})
      assert cs.valid?
    end

    test "requires expires_at", %{attrs: attrs} do
      cs = Invitation.changeset(%Invitation{}, Map.delete(attrs, :expires_at))
      refute cs.valid?
      assert "can't be blank" in errors_on(cs).expires_at
    end

    test "requires token_hash", %{attrs: attrs} do
      cs = Invitation.changeset(%Invitation{}, Map.delete(attrs, :token_hash))
      refute cs.valid?
      assert "can't be blank" in errors_on(cs).token_hash
    end

    test "requires organization_id", %{attrs: attrs} do
      cs = Invitation.changeset(%Invitation{}, Map.delete(attrs, :organization_id))
      refute cs.valid?
      assert "can't be blank" in errors_on(cs).organization_id
    end
  end
end
