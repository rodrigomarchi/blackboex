defmodule Blackboex.FeaturesTest do
  use Blackboex.DataCase, async: false

  alias Blackboex.Features
  alias Blackboex.Organizations

  import Blackboex.AccountsFixtures

  @moduletag :unit

  setup do
    # Clean up any flags from previous tests
    :ok
  end

  describe "enabled?/2" do
    test "returns false when flag is not set" do
      user = user_fixture()
      refute Features.enabled?(:some_random_flag, user)
    end

    test "returns true when flag is globally enabled" do
      user = user_fixture()
      {:ok, true} = Features.enable(:test_global_flag)

      assert Features.enabled?(:test_global_flag, user)

      # cleanup
      Features.disable(:test_global_flag)
    end

    test "returns false when flag is globally disabled" do
      user = user_fixture()
      {:ok, false} = Features.disable(:test_disabled_flag)

      refute Features.enabled?(:test_disabled_flag, user)
    end

    test "returns true when flag is enabled for nil user (global check)" do
      {:ok, true} = Features.enable(:test_nil_flag)

      assert Features.enabled?(:test_nil_flag, nil)

      Features.disable(:test_nil_flag)
    end
  end

  describe "enable/2 and disable/2" do
    test "enable and disable a flag globally" do
      {:ok, true} = Features.enable(:toggle_flag)
      user = user_fixture()

      assert Features.enabled?(:toggle_flag, user)

      {:ok, false} = Features.disable(:toggle_flag)

      refute Features.enabled?(:toggle_flag, user)
    end

    test "enable flag for a specific actor" do
      user1 = user_fixture()
      user2 = user_fixture()

      {:ok, true} = Features.enable(:actor_flag, for_actor: user1)

      assert Features.enabled?(:actor_flag, user1)
      refute Features.enabled?(:actor_flag, user2)

      Features.disable(:actor_flag, for_actor: user1)
    end
  end

  describe "FunWithFlags.Actor protocol" do
    test "returns namespaced ID for user" do
      user = user_fixture()
      assert FunWithFlags.Actor.id(user) == "user:#{user.id}"
    end
  end

  describe "FunWithFlags.Group protocol" do
    test "free user is not in :pro group" do
      user = user_fixture()
      refute FunWithFlags.Group.in?(user, :pro)
    end

    test "free user is not in :enterprise group" do
      user = user_fixture()
      refute FunWithFlags.Group.in?(user, :enterprise)
    end

    test "pro user is in :pro group" do
      user = user_fixture()
      [org] = Organizations.list_user_organizations(user)

      org
      |> Ecto.Changeset.change(plan: :pro)
      |> Blackboex.Repo.update!()

      assert FunWithFlags.Group.in?(user, :pro)
      refute FunWithFlags.Group.in?(user, :enterprise)
    end

    test "enterprise user is in both :pro and :enterprise groups" do
      user = user_fixture()
      [org] = Organizations.list_user_organizations(user)

      org
      |> Ecto.Changeset.change(plan: :enterprise)
      |> Blackboex.Repo.update!()

      assert FunWithFlags.Group.in?(user, :pro)
      assert FunWithFlags.Group.in?(user, :enterprise)
    end

    test "group-gated flag works with for_group" do
      user = user_fixture()
      [org] = Organizations.list_user_organizations(user)

      org
      |> Ecto.Changeset.change(plan: :pro)
      |> Blackboex.Repo.update!()

      {:ok, true} = Features.enable(:pro_feature, for_group: :pro)

      assert Features.enabled?(:pro_feature, user)

      Features.disable(:pro_feature, for_group: :pro)
    end

    test "free user cannot access pro group-gated flag" do
      user = user_fixture()

      {:ok, true} = Features.enable(:pro_only, for_group: :pro)

      refute Features.enabled?(:pro_only, user)

      Features.disable(:pro_only, for_group: :pro)
    end
  end
end
