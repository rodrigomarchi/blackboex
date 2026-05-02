defmodule Blackboex.Samples.ManifestTest do
  use Blackboex.DataCase, async: true

  alias Blackboex.Apis.Templates, as: ApiTemplates
  alias Blackboex.Flows.Templates, as: FlowTemplates
  alias Blackboex.Samples.Manifest

  @valid_kinds [:api, :flow, :page, :playground]

  describe "version/0" do
    test "returns a non-empty manifest version" do
      assert Manifest.version() |> is_binary()
      assert Manifest.version() != ""
    end
  end

  describe "list/0" do
    test "all samples have required identity fields" do
      for sample <- Manifest.list() do
        assert sample.kind in @valid_kinds
        assert is_binary(sample.id) and sample.id != ""
        assert is_binary(sample.sample_uuid) and sample.sample_uuid != ""
        assert {:ok, _} = Ecto.UUID.cast(sample.sample_uuid)
        assert is_binary(sample.name) and sample.name != ""
        assert is_binary(sample.description) and sample.description != ""
        assert is_binary(sample.category) and sample.category != ""
      end
    end

    test "sample UUIDs are globally unique" do
      uuids = Enum.map(Manifest.list(), & &1.sample_uuid)
      assert uuids == Enum.uniq(uuids)
    end

    test "sample ids are unique inside each kind" do
      for kind <- @valid_kinds do
        ids = kind |> Manifest.list_by_kind() |> Enum.map(& &1.id)
        assert ids == Enum.uniq(ids)
      end
    end

    test "api and flow adapters expose the manifest as their source" do
      api_ids = :api |> Manifest.list_by_kind() |> Enum.map(& &1.id) |> MapSet.new()
      flow_ids = :flow |> Manifest.list_by_kind() |> Enum.map(& &1.id) |> MapSet.new()

      assert api_ids == ApiTemplates.list() |> Enum.map(& &1.id) |> MapSet.new()
      assert flow_ids == FlowTemplates.list() |> Enum.map(& &1.id) |> MapSet.new()
    end

    test "page parent references point to page samples" do
      page_uuids =
        :page
        |> Manifest.list_by_kind()
        |> Enum.map(& &1.sample_uuid)
        |> MapSet.new()

      for page <- Manifest.list_by_kind(:page),
          parent_uuid = Map.get(page, :parent_sample_uuid),
          not is_nil(parent_uuid) do
        assert MapSet.member?(page_uuids, parent_uuid)
      end
    end

    test "playground flow references point to flow samples" do
      flow_uuids =
        :flow
        |> Manifest.list_by_kind()
        |> Enum.map(& &1.sample_uuid)
        |> MapSet.new()

      for playground <- Manifest.list_by_kind(:playground),
          flow_uuid = Map.get(playground, :flow_sample_uuid),
          not is_nil(flow_uuid) do
        assert MapSet.member?(flow_uuids, flow_uuid)
      end
    end
  end

  describe "lookups" do
    test "get_by_uuid/1 and get_by_kind_and_id/2 return manifest samples" do
      sample = Manifest.list() |> hd()

      assert Manifest.get_by_uuid(sample.sample_uuid) == sample
      assert Manifest.get_by_kind_and_id(sample.kind, sample.id) == sample
    end

    test "list_by_kind/1 filters samples" do
      assert Enum.all?(Manifest.list_by_kind(:api), &(&1.kind == :api))
      assert Enum.all?(Manifest.list_by_kind(:flow), &(&1.kind == :flow))
      assert Enum.all?(Manifest.list_by_kind(:page), &(&1.kind == :page))
      assert Enum.all?(Manifest.list_by_kind(:playground), &(&1.kind == :playground))
    end
  end
end
