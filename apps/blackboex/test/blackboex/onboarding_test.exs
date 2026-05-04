defmodule Blackboex.OnboardingTest do
  use Blackboex.DataCase, async: false

  alias Blackboex.Accounts
  alias Blackboex.Accounts.User
  alias Blackboex.Onboarding
  alias Blackboex.Organizations
  alias Blackboex.Organizations.{Membership, Organization}
  alias Blackboex.Projects.{Project, ProjectMembership}
  alias Blackboex.Settings

  setup do
    Settings.invalidate_cache()
    on_exit(fn -> Settings.invalidate_cache() end)
    :ok
  end

  defp valid_attrs(overrides \\ %{}) do
    Enum.into(overrides, %{
      app_name: "Blackboex",
      public_url: "http://localhost:4000",
      email: "owner@example.com",
      password: "supersecret123",
      org_name: "Acme"
    })
  end

  describe "complete_first_run/1 — happy path" do
    test "creates user, org, project, membership, settings in one tx" do
      before_users = Repo.aggregate(User, :count, :id)
      before_orgs = Repo.aggregate(Organization, :count, :id)
      before_projects = Repo.aggregate(Project, :count, :id)
      before_memberships = Repo.aggregate(Membership, :count, :id)
      before_pms = Repo.aggregate(ProjectMembership, :count, :id)

      assert {:ok, %{user: user, organization: org, project: project}} =
               Onboarding.complete_first_run(valid_attrs())

      assert %User{} = user
      assert %Organization{} = org
      assert %Project{} = project
      assert Repo.aggregate(User, :count, :id) == before_users + 1
      assert Repo.aggregate(Organization, :count, :id) == before_orgs + 1
      assert Repo.aggregate(Project, :count, :id) == before_projects + 1
      assert Repo.aggregate(Membership, :count, :id) == before_memberships + 1
      assert Repo.aggregate(ProjectMembership, :count, :id) == before_pms + 1
      assert Settings.get_settings() != nil
    end

    test "user is platform admin and confirmed" do
      assert {:ok, %{user: user}} = Onboarding.complete_first_run(valid_attrs())
      assert user.is_platform_admin == true
      assert user.confirmed_at != nil
    end

    test "user can authenticate with the password set" do
      assert {:ok, %{user: user}} = Onboarding.complete_first_run(valid_attrs())

      assert %User{id: id} =
               Accounts.get_user_by_email_and_password(user.email, "supersecret123")

      assert id == user.id
    end

    test "membership has role :owner" do
      assert {:ok, %{user: user, organization: org}} =
               Onboarding.complete_first_run(valid_attrs())

      membership = Organizations.get_user_membership(org, user)
      assert membership.role == :owner
    end

    test "project is the managed sample workspace" do
      assert {:ok, %{project: project}} =
               Onboarding.complete_first_run(valid_attrs(%{project_name: "MyProj"}))

      assert project.name == "Examples"
      assert project.sample_workspace == true
    end

    test "settings record stores app_name and public_url" do
      assert {:ok, _} =
               Onboarding.complete_first_run(
                 valid_attrs(%{app_name: "Custom App", public_url: "https://example.com"})
               )

      settings = Settings.get_settings()
      assert settings.app_name == "Custom App"
      assert settings.public_url == "https://example.com"
    end

    test "Settings.setup_completed?/0 returns true after success" do
      refute Settings.setup_completed?()
      assert {:ok, _} = Onboarding.complete_first_run(valid_attrs())
      assert Settings.setup_completed?()
    end
  end

  describe "complete_first_run/1 — guards" do
    test "returns {:error, :already_completed} when settings exist" do
      assert {:ok, _} = Onboarding.complete_first_run(valid_attrs())

      assert {:error, :already_completed} =
               Onboarding.complete_first_run(
                 valid_attrs(%{email: "second@example.com", org_name: "Other"})
               )
    end

    test "returns {:error, %Ecto.Changeset{}} on invalid email" do
      assert {:error, %Ecto.Changeset{} = cs} =
               Onboarding.complete_first_run(valid_attrs(%{email: "not-an-email"}))

      assert "is invalid" in (errors_on(cs)[:email] || []) or
               errors_on(cs)[:email] != nil
    end

    test "returns {:error, %Ecto.Changeset{}} on invalid password (too short)" do
      assert {:error, %Ecto.Changeset{} = cs} =
               Onboarding.complete_first_run(valid_attrs(%{password: "short"}))

      assert errors_on(cs)[:password] != nil
    end

    test "returns {:error, %Ecto.Changeset{}} on blank org_name" do
      assert {:error, %Ecto.Changeset{} = cs} =
               Onboarding.complete_first_run(valid_attrs(%{org_name: ""}))

      assert errors_on(cs)[:org_name] != nil
    end

    test "returns {:error, %Ecto.Changeset{}} on invalid public_url" do
      assert {:error, %Ecto.Changeset{} = cs} =
               Onboarding.complete_first_run(valid_attrs(%{public_url: "not-a-url"}))

      assert errors_on(cs)[:public_url] != nil
    end
  end

  describe "complete_first_run/1 — atomicity" do
    test "rolls back everything when org creation fails (no User row remains)" do
      before_users = Repo.aggregate(User, :count, :id)
      before_orgs = Repo.aggregate(Organization, :count, :id)

      # Org with empty name will fail validation upstream; ensure no rows added.
      assert {:error, _} =
               Onboarding.complete_first_run(valid_attrs(%{org_name: "  "}))

      assert Repo.aggregate(User, :count, :id) == before_users
      assert Repo.aggregate(Organization, :count, :id) == before_orgs
      refute Settings.setup_completed?()
    end
  end

  describe "complete_first_run/1 — race" do
    test "concurrent calls: only one succeeds, the other gets :already_completed" do
      parent = self()
      before_users = Repo.aggregate(User, :count, :id)

      # async:false => sandbox is in shared mode (owner = test pid); child
      # processes pick up the connection automatically via `:shared` mode.
      results =
        1..5
        |> Task.async_stream(
          fn i ->
            _ = parent

            Onboarding.complete_first_run(
              valid_attrs(%{email: "user#{i}@example.com", org_name: "Org#{i}"})
            )
          end,
          max_concurrency: 5,
          ordered: false,
          timeout: 10_000
        )
        |> Enum.map(fn {:ok, r} -> r end)

      successes = Enum.count(results, &match?({:ok, _}, &1))
      already = Enum.count(results, &match?({:error, :already_completed}, &1))

      assert successes == 1
      assert successes + already == 5
      assert Repo.aggregate(User, :count, :id) == before_users + 1
    end
  end
end
