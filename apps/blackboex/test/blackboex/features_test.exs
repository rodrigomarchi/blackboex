defmodule Blackboex.FeaturesTest do
  use Blackboex.DataCase, async: false

  alias Blackboex.Features
  alias Blackboex.ProjectEnvVars

  setup [:create_user_and_org, :create_project]

  describe "project_agent_enabled?/1" do
    test "returns the application config default when no overrides", %{project: project} do
      previous = Application.get_env(:blackboex, :features, [])

      try do
        Application.put_env(:blackboex, :features, project_agent: true)
        assert Features.project_agent_enabled?(project) == true

        Application.put_env(:blackboex, :features, project_agent: false)
        assert Features.project_agent_enabled?(project) == false
      after
        Application.put_env(:blackboex, :features, previous)
      end
    end

    test "per-project ProjectEnvVars override takes precedence", %{
      project: project,
      org: org
    } do
      previous = Application.get_env(:blackboex, :features, [])

      try do
        Application.put_env(:blackboex, :features, project_agent: false)

        {:ok, _ev} =
          ProjectEnvVars.create(%{
            project_id: project.id,
            organization_id: org.id,
            name: "FEATURE_PROJECT_AGENT",
            value: "true"
          })

        assert Features.project_agent_enabled?(project) == true
      after
        Application.put_env(:blackboex, :features, previous)
      end
    end

    test "per-project override of \"false\" disables when config default is true", %{
      project: project,
      org: org
    } do
      previous = Application.get_env(:blackboex, :features, [])

      try do
        Application.put_env(:blackboex, :features, project_agent: true)

        {:ok, _ev} =
          ProjectEnvVars.create(%{
            project_id: project.id,
            organization_id: org.id,
            name: "FEATURE_PROJECT_AGENT",
            value: "false"
          })

        assert Features.project_agent_enabled?(project) == false
      after
        Application.put_env(:blackboex, :features, previous)
      end
    end

    test "ignores non-true/false override values and falls back", %{
      project: project,
      org: org
    } do
      previous = Application.get_env(:blackboex, :features, [])

      try do
        Application.put_env(:blackboex, :features, project_agent: true)

        {:ok, _ev} =
          ProjectEnvVars.create(%{
            project_id: project.id,
            organization_id: org.id,
            name: "FEATURE_PROJECT_AGENT",
            value: "garbage"
          })

        assert Features.project_agent_enabled?(project) == true
      after
        Application.put_env(:blackboex, :features, previous)
      end
    end
  end
end
