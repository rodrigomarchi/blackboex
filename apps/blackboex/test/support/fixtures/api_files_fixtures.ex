defmodule Blackboex.ApiFilesFixtures do
  @moduledoc """
  Test helpers for creating API file system entities.
  """

  alias Blackboex.Apis
  alias Blackboex.Apis.{ApiFile, ApiFileRevision}
  alias Blackboex.Repo

  @doc """
  Creates an ApiFile for the given API.

  ## Options

    * `:api_id` - (required) the API ID
    * `:path` - file path (default: "/src/handler.ex")
    * `:content` - file content (default: handler skeleton)
    * `:file_type` - "source" | "test" (default: inferred from path)

  Returns the file struct.
  """
  @spec api_file_fixture(map()) :: ApiFile.t()
  def api_file_fixture(attrs) do
    api = attrs[:api] || raise "api_file_fixture requires :api"
    path = attrs[:path] || "/src/handler.ex"

    file_type =
      attrs[:file_type] ||
        if(String.starts_with?(path, "/test"), do: "test", else: "source")

    content = attrs[:content] || default_content(path)

    {:ok, file} =
      Apis.create_file(api, %{
        path: path,
        content: content,
        file_type: file_type,
        source: attrs[:source] || "generation",
        created_by_id: attrs[:created_by_id]
      })

    file
  end

  @doc """
  Creates the default file pair for an API: /src/handler.ex + /test/handler_test.ex.

  Returns `{handler_file, test_file}`.
  """
  @spec default_files_fixture(Blackboex.Apis.Api.t(), map()) ::
          {ApiFile.t(), ApiFile.t()}
  def default_files_fixture(api, attrs \\ %{}) do
    handler =
      api_file_fixture(%{
        api: api,
        path: "/src/handler.ex",
        content: attrs[:handler_content] || default_handler_code(),
        file_type: "source"
      })

    test =
      api_file_fixture(%{
        api: api,
        path: "/test/handler_test.ex",
        content: attrs[:test_content] || default_test_code(),
        file_type: "test"
      })

    {handler, test}
  end

  @doc """
  Gets the latest revision for a file.
  """
  @spec latest_revision(ApiFile.t()) :: ApiFileRevision.t() | nil
  def latest_revision(%ApiFile{id: file_id}) do
    import Ecto.Query

    ApiFileRevision
    |> where([r], r.api_file_id == ^file_id)
    |> order_by([r], desc: r.revision_number)
    |> limit(1)
    |> Repo.one()
  end

  defp default_content("/src/handler.ex"), do: default_handler_code()
  defp default_content("/test/handler_test.ex"), do: default_test_code()
  defp default_content(_path), do: ""

  defp default_handler_code do
    """
    def handle(params) do
      %{result: "ok"}
    end
    """
  end

  defp default_test_code do
    """
    defmodule HandlerTest do
      use ExUnit.Case, async: true

      test "returns ok" do
        assert Handler.handle(%{}) == %{result: "ok"}
      end
    end
    """
  end
end
