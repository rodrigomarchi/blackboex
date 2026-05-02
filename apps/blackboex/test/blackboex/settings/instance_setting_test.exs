defmodule Blackboex.Settings.InstanceSettingTest do
  use Blackboex.DataCase, async: false

  alias Blackboex.Settings.InstanceSetting

  describe "changeset/2" do
    test "valid with required fields (app_name, public_url)" do
      attrs = %{
        app_name: "My App",
        public_url: "https://example.com",
        setup_completed_at: DateTime.utc_now()
      }

      changeset = InstanceSetting.changeset(%InstanceSetting{id: 1}, attrs)
      assert changeset.valid?
    end

    test "invalid public_url returns error" do
      for bad_url <- ["not-a-url", "ftp://x"] do
        attrs = %{
          app_name: "My App",
          public_url: bad_url,
          setup_completed_at: DateTime.utc_now()
        }

        changeset = InstanceSetting.changeset(%InstanceSetting{id: 1}, attrs)
        refute changeset.valid?
        assert "must be a valid http(s) URL" in errors_on(changeset).public_url
      end
    end

    test "valid public_url accepts http and https" do
      for ok_url <- ["http://localhost:4000", "https://example.com"] do
        attrs = %{
          app_name: "My App",
          public_url: ok_url,
          setup_completed_at: DateTime.utc_now()
        }

        changeset = InstanceSetting.changeset(%InstanceSetting{id: 1}, attrs)
        assert changeset.valid?, "expected #{ok_url} to be valid"
      end
    end

    test "blank app_name returns error" do
      attrs = %{
        app_name: "",
        public_url: "https://example.com",
        setup_completed_at: DateTime.utc_now()
      }

      changeset = InstanceSetting.changeset(%InstanceSetting{id: 1}, attrs)
      refute changeset.valid?
      assert "can't be blank" in errors_on(changeset).app_name
    end

    test "blank public_url returns error" do
      attrs = %{
        app_name: "My App",
        public_url: "",
        setup_completed_at: DateTime.utc_now()
      }

      changeset = InstanceSetting.changeset(%InstanceSetting{id: 1}, attrs)
      refute changeset.valid?
      assert "can't be blank" in errors_on(changeset).public_url
    end
  end
end
