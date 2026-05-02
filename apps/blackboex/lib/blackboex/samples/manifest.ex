defmodule Blackboex.Samples.Manifest do
  @moduledoc """
  Single source of truth for platform samples.
  """

  alias Blackboex.Samples.{Api, Flow, Page, Playground}

  @version "2026-05-02.1"

  @type kind :: :api | :flow | :page | :playground
  @type sample :: map()

  @spec version() :: String.t()
  def version, do: @version

  @spec list() :: [sample()]
  def list do
    Api.list() ++ Flow.list() ++ Page.list() ++ Playground.list()
  end

  @spec list_by_kind(kind()) :: [sample()]
  def list_by_kind(kind) do
    Enum.filter(list(), &(&1.kind == kind))
  end

  @spec get_by_uuid(Ecto.UUID.t()) :: sample() | nil
  def get_by_uuid(sample_uuid) when is_binary(sample_uuid) do
    Enum.find(list(), &(&1.sample_uuid == sample_uuid))
  end

  @spec get_by_kind_and_id(kind(), String.t()) :: sample() | nil
  def get_by_kind_and_id(kind, id) when is_binary(id) do
    Enum.find(list_by_kind(kind), &(&1.id == id))
  end
end
