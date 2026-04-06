defmodule Blackboex.Organizations.MembershipTest do
  use Blackboex.DataCase, async: true

  alias Blackboex.Organizations.{Membership, Organization}

  @moduletag :unit
  describe "changeset/2" do
    test "valid with user_id, organization_id, and role" do
      user = user_fixture()

      {:ok, org} =
        %Organization{}
        |> Organization.changeset(%{name: "Test Org"})
        |> Blackboex.Repo.insert()

      changeset =
        Membership.changeset(%Membership{}, %{
          user_id: user.id,
          organization_id: org.id,
          role: :owner
        })

      assert changeset.valid?
    end

    test "validates role is one of :owner, :admin, :member" do
      changeset = Membership.changeset(%Membership{}, %{role: :invalid})
      refute changeset.valid?
      assert "is invalid" in errors_on(changeset).role
    end

    test "unique constraint on user_id + organization_id" do
      user = user_fixture()

      {:ok, org} =
        %Organization{}
        |> Organization.changeset(%{name: "Test Org"})
        |> Blackboex.Repo.insert()

      {:ok, _membership} =
        %Membership{}
        |> Membership.changeset(%{user_id: user.id, organization_id: org.id, role: :owner})
        |> Blackboex.Repo.insert()

      {:error, changeset} =
        %Membership{}
        |> Membership.changeset(%{user_id: user.id, organization_id: org.id, role: :member})
        |> Blackboex.Repo.insert()

      assert "has already been taken" in errors_on(changeset).user_id
    end
  end
end
