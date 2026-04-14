defmodule Blackboex.FlowSecretsFixtures do
  @moduledoc """
  Test helpers for creating FlowSecret entities.
  """

  alias Blackboex.FlowSecrets

  @doc """
  Creates a flow secret for the given organization.

  If no `organization_id` is provided, creates a new org automatically.

  ## Options

    * `:organization_id` - the organization UUID (default: auto-created)
    * `:name` - secret name (default: auto-generated)
    * `:value` - plaintext secret value (default: "test_secret_value")

  Returns the FlowSecret struct.
  """
  @spec flow_secret_fixture(map()) :: Blackboex.FlowSecrets.FlowSecret.t()
  def flow_secret_fixture(attrs \\ %{}) do
    org_id =
      attrs[:organization_id] ||
        Blackboex.OrganizationsFixtures.org_fixture().id

    project_id =
      attrs[:project_id] ||
        (Blackboex.Projects.get_default_project(org_id) || %{id: nil}).id

    uid = System.unique_integer([:positive])

    {:ok, secret} =
      FlowSecrets.create_secret(%{
        organization_id: org_id,
        project_id: project_id,
        name: attrs[:name] || "secret_#{uid}",
        value: attrs[:value] || "test_secret_value"
      })

    secret
  end
end
