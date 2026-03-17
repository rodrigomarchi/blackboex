defmodule Blackboex.Apis.ApiTest do
  use Blackboex.DataCase, async: true

  @moduletag :unit

  alias Blackboex.Apis.Api

  @valid_attrs %{
    name: "Temperature Converter",
    slug: "temperature-converter",
    description: "Converts Celsius to Fahrenheit",
    template_type: "computation",
    method: "POST"
  }

  describe "changeset/2" do
    test "valid with all required fields" do
      changeset = Api.changeset(%Api{}, @valid_attrs)
      assert changeset.valid?
    end

    test "generates slug from name if not provided" do
      attrs = Map.delete(@valid_attrs, :slug)
      changeset = Api.changeset(%Api{}, attrs)
      assert changeset.valid?
      assert get_change(changeset, :slug) == "temperature-converter"
    end

    test "validates required fields" do
      changeset = Api.changeset(%Api{}, %{})
      refute changeset.valid?
      assert %{name: ["can't be blank"]} = errors_on(changeset)
    end

    test "status defaults to draft" do
      changeset = Api.changeset(%Api{}, @valid_attrs)
      assert get_field(changeset, :status) == "draft"
    end

    test "validates template_type inclusion" do
      changeset = Api.changeset(%Api{}, %{@valid_attrs | template_type: "invalid"})
      refute changeset.valid?
      assert %{template_type: [_]} = errors_on(changeset)
    end

    test "accepts valid template types" do
      for type <- ~w(computation crud webhook) do
        changeset = Api.changeset(%Api{}, %{@valid_attrs | template_type: type})
        assert changeset.valid?, "Expected #{type} to be valid"
      end
    end

    test "method defaults to POST" do
      attrs = Map.delete(@valid_attrs, :method)
      changeset = Api.changeset(%Api{}, attrs)
      assert get_field(changeset, :method) == "POST"
    end

    test "validates slug format" do
      changeset = Api.changeset(%Api{}, %{@valid_attrs | slug: "INVALID SLUG!"})
      refute changeset.valid?
      assert %{slug: [_]} = errors_on(changeset)
    end

    test "validates slug length" do
      changeset = Api.changeset(%Api{}, %{@valid_attrs | slug: String.duplicate("a", 101)})
      refute changeset.valid?
      assert %{slug: [_]} = errors_on(changeset)
    end

    test "slug handles unicode by stripping non-ascii" do
      changeset =
        Api.changeset(%Api{}, %{@valid_attrs | name: "Conversão de Temperatura", slug: nil})

      assert changeset.valid?
      slug = get_change(changeset, :slug)
      assert slug =~ ~r/^[a-z0-9]([a-z0-9-]*[a-z0-9])?$/
    end

    test "slug handles empty name gracefully" do
      changeset = Api.changeset(%Api{}, %{@valid_attrs | name: "", slug: nil})
      refute changeset.valid?
    end

    test "validates name max length" do
      changeset = Api.changeset(%Api{}, %{@valid_attrs | name: String.duplicate("a", 201)})
      refute changeset.valid?
      assert %{name: [_]} = errors_on(changeset)
    end

    test "validates description max length" do
      changeset =
        Api.changeset(%Api{}, %{@valid_attrs | description: String.duplicate("a", 10_001)})

      refute changeset.valid?
      assert %{description: [_]} = errors_on(changeset)
    end

    test "validates status inclusion" do
      changeset = Api.changeset(%Api{}, Map.put(@valid_attrs, :status, "invalid"))
      refute changeset.valid?
      assert %{status: [_]} = errors_on(changeset)
    end

    test "accepts valid statuses" do
      for status <- ~w(draft active archived) do
        changeset = Api.changeset(%Api{}, Map.put(@valid_attrs, :status, status))
        assert changeset.valid?, "Expected #{status} to be valid"
      end
    end

    test "validates method inclusion" do
      changeset = Api.changeset(%Api{}, %{@valid_attrs | method: "INVALID"})
      refute changeset.valid?
      assert %{method: [_]} = errors_on(changeset)
    end
  end
end
