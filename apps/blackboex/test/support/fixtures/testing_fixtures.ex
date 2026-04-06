defmodule Blackboex.TestingFixtures do
  @moduledoc """
  Test helpers for creating testing domain entities.
  """

  alias Blackboex.Repo
  alias Blackboex.Testing.TestSuite

  @doc """
  Creates a test suite for the given API.

  ## Required

    * `:api_id` - the API ID

  ## Optional

    * `:test_code` - the test code (default: "test code")
    * `:status` - suite status (default: "pending")
    * Any other TestSuite fields

  Returns the test suite struct.
  """
  @spec test_suite_fixture(map()) :: TestSuite.t()
  def test_suite_fixture(attrs) do
    {:ok, suite} =
      %TestSuite{}
      |> TestSuite.changeset(
        Map.merge(
          %{
            test_code: "test code"
          },
          attrs
        )
      )
      |> Repo.insert()

    suite
  end
end
