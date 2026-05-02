defmodule Blackboex.InstanceSettingsFixtures do
  @moduledoc "Fixtures for `Blackboex.Settings`."

  alias Blackboex.Settings

  @spec valid_instance_setting_attributes(map()) :: map()
  def valid_instance_setting_attributes(attrs \\ %{}) do
    Enum.into(attrs, %{
      app_name: "Blackboex",
      public_url: "http://localhost:4000"
    })
  end

  @spec instance_setting_fixture(map()) :: Blackboex.Settings.InstanceSetting.t()
  def instance_setting_fixture(attrs \\ %{}) do
    Settings.invalidate_cache()

    attrs
    |> valid_instance_setting_attributes()
    |> Settings.mark_setup_completed!()
  end
end
