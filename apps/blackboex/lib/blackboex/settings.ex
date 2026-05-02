defmodule Blackboex.Settings do
  @moduledoc "Singleton instance settings + first-run completion check."

  alias Blackboex.Repo
  alias Blackboex.Settings.InstanceSetting

  @cache_key {__MODULE__, :setup_completed?}

  @spec setup_completed?() :: boolean()
  def setup_completed? do
    case :persistent_term.get(@cache_key, :miss) do
      :miss ->
        completed = Repo.exists?(InstanceSetting)
        :persistent_term.put(@cache_key, completed)
        completed

      cached ->
        cached
    end
  end

  @spec mark_setup_completed!(map()) :: InstanceSetting.t()
  def mark_setup_completed!(attrs) do
    settings =
      %InstanceSetting{id: 1}
      |> InstanceSetting.changeset(Map.put_new(attrs, :setup_completed_at, DateTime.utc_now()))
      |> Repo.insert!()

    :persistent_term.put(@cache_key, true)
    settings
  end

  @spec get_settings() :: InstanceSetting.t() | nil
  def get_settings, do: Repo.get(InstanceSetting, 1)

  @doc false
  @spec invalidate_cache() :: :ok
  def invalidate_cache do
    :persistent_term.erase(@cache_key)
    :ok
  end
end
