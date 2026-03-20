defmodule Blackboex.Factory do
  @moduledoc """
  ExMachina factory for test data generation.
  """

  use ExMachina.Ecto, repo: Blackboex.Repo

  alias Blackboex.Apis.Api

  @spec api_factory() :: Api.t()
  def api_factory do
    %Api{
      name: sequence(:api_name, &"Test API #{&1}"),
      slug: sequence(:api_slug, &"test-api-#{&1}"),
      description: "A test API",
      source_code: "defmodule Api do\n  def call(params), do: {:ok, params}\nend",
      template_type: "computation",
      method: "POST",
      status: "draft",
      visibility: "private",
      requires_auth: true,
      param_schema: %{"type" => "object", "properties" => %{}},
      example_request: %{"key" => "value"},
      example_response: %{"result" => "ok"},
      organization_id: nil,
      user_id: nil
    }
  end
end
