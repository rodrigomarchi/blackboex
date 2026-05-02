defmodule Blackboex.SettingsTest do
  use Blackboex.DataCase, async: false

  alias Blackboex.Settings
  alias Blackboex.Settings.InstanceSetting

  setup :clear_settings_cache

  defp clear_settings_cache(_ctx) do
    Settings.invalidate_cache()
    :ok
  end

  describe "setup_completed?/0" do
    test "returns false when no instance_setting row exists" do
      refute Settings.setup_completed?()
    end

    test "returns true after mark_setup_completed!/1" do
      Settings.mark_setup_completed!(%{
        app_name: "Blackboex",
        public_url: "http://localhost:4000"
      })

      assert Settings.setup_completed?()
    end

    test "uses :persistent_term cache (does not re-query DB)" do
      Settings.mark_setup_completed!(%{
        app_name: "Blackboex",
        public_url: "http://localhost:4000"
      })

      assert Settings.setup_completed?()

      # Bypass the context to bust DB state without invalidating the cache.
      Repo.delete_all(InstanceSetting)

      # Cache still serves true.
      assert Settings.setup_completed?()

      # Explicit invalidation now reflects the empty DB.
      Settings.invalidate_cache()
      refute Settings.setup_completed?()
    end
  end

  describe "mark_setup_completed!/1" do
    test "inserts singleton with given app_name and public_url and sets setup_completed_at" do
      settings =
        Settings.mark_setup_completed!(%{
          app_name: "Blackboex",
          public_url: "http://localhost:4000"
        })

      assert settings.id == 1
      assert settings.app_name == "Blackboex"
      assert settings.public_url == "http://localhost:4000"
      assert %DateTime{} = settings.setup_completed_at
    end

    test "raises when called twice (singleton constraint)" do
      Settings.mark_setup_completed!(%{
        app_name: "Blackboex",
        public_url: "http://localhost:4000"
      })

      assert_raise Ecto.ConstraintError, fn ->
        Settings.mark_setup_completed!(%{
          app_name: "Other",
          public_url: "http://localhost:4001"
        })
      end
    end

    test "invalidates cache so subsequent setup_completed?/0 reflects new state" do
      refute Settings.setup_completed?()

      Settings.mark_setup_completed!(%{
        app_name: "Blackboex",
        public_url: "http://localhost:4000"
      })

      assert Settings.setup_completed?()
    end
  end

  describe "get_settings/0" do
    test "returns nil before setup" do
      assert Settings.get_settings() == nil
    end

    test "returns the singleton struct after setup" do
      Settings.mark_setup_completed!(%{
        app_name: "Blackboex",
        public_url: "http://localhost:4000"
      })

      assert %InstanceSetting{id: 1, app_name: "Blackboex"} = Settings.get_settings()
    end
  end
end
