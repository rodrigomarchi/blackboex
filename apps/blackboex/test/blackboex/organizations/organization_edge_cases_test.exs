defmodule Blackboex.Organizations.OrganizationEdgeCasesTest do
  use Blackboex.DataCase, async: true

  alias Blackboex.Organizations.Organization

  @moduletag :unit

  describe "slug generation edge cases" do
    test "special characters only produces empty slug — fails required" do
      changeset = Organization.changeset(%Organization{}, %{name: "!!!"})
      refute changeset.valid?
      assert "can't be blank" in errors_on(changeset).slug
    end

    test "spaces only produces invalid slug" do
      changeset = Organization.changeset(%Organization{}, %{name: "   "})
      refute changeset.valid?
    end

    test "unicode characters are stripped from slug" do
      changeset = Organization.changeset(%Organization{}, %{name: "Café"})
      assert changeset.valid?
      assert Ecto.Changeset.get_change(changeset, :slug) == "caf"
    end

    test "very long name produces valid slug" do
      name = String.duplicate("a", 200)
      changeset = Organization.changeset(%Organization{}, %{name: name})
      refute changeset.valid?
      assert "should be at most 100 character(s)" in errors_on(changeset).slug
    end

    test "name with leading/trailing special chars" do
      changeset = Organization.changeset(%Organization{}, %{name: "---my org---"})
      assert changeset.valid?
      assert Ecto.Changeset.get_change(changeset, :slug) == "my-org"
    end

    test "directly provided invalid slug format is rejected" do
      changeset =
        Organization.changeset(%Organization{}, %{name: "My Org", slug: "INVALID SLUG!"})

      refute changeset.valid?

      assert "must contain only lowercase letters, numbers, and hyphens, and not start/end with a hyphen" in errors_on(
               changeset
             ).slug
    end

    test "directly provided valid slug is accepted" do
      changeset = Organization.changeset(%Organization{}, %{name: "My Org", slug: "custom-slug"})
      assert changeset.valid?
      assert Ecto.Changeset.get_change(changeset, :slug) == "custom-slug"
    end
  end
end
