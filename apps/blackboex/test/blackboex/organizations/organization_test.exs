defmodule Blackboex.Organizations.OrganizationTest do
  use Blackboex.DataCase, async: true

  alias Blackboex.Organizations.Organization

  @moduletag :unit
  describe "changeset/2" do
    test "valid with name and slug" do
      changeset = Organization.changeset(%Organization{}, %{name: "My Org", slug: "my-org"})
      assert changeset.valid?
    end

    test "generates slug automatically from name" do
      changeset = Organization.changeset(%Organization{}, %{name: "My Cool Org"})
      assert changeset.valid?
      assert Ecto.Changeset.get_change(changeset, :slug) == "my-cool-org"
    end

    test "requires name" do
      changeset = Organization.changeset(%Organization{}, %{})
      refute changeset.valid?
      assert "can't be blank" in errors_on(changeset).name
    end

    test "slug must be unique" do
      {:ok, _org} =
        %Organization{}
        |> Organization.changeset(%{name: "First Org", slug: "unique-slug"})
        |> Blackboex.Repo.insert()

      {:error, changeset} =
        %Organization{}
        |> Organization.changeset(%{name: "Second Org", slug: "unique-slug"})
        |> Blackboex.Repo.insert()

      assert "has already been taken" in errors_on(changeset).slug
    end

    test "defaults plan to :free" do
      changeset = Organization.changeset(%Organization{}, %{name: "My Org"})
      # plan default is set in schema, not changeset
      org = Ecto.Changeset.apply_changes(changeset)
      assert org.plan == :free
    end
  end
end
