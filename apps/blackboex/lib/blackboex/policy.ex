defmodule Blackboex.Policy do
  @moduledoc """
  Authorization policy using LetMe DSL.
  Defines RBAC rules for organizations and memberships.
  """
  use LetMe.Policy

  alias Blackboex.Telemetry.Events

  @doc "Authorize with telemetry: emits [:blackboex, :policy, :denied] on failure."
  @spec authorize_and_track(atom(), term(), term()) :: :ok | {:error, :unauthorized}
  def authorize_and_track(action, scope, object) do
    case authorize(action, scope, object) do
      :ok ->
        :ok

      {:error, _} = error ->
        user_id =
          case scope do
            %{user: %{id: id}} -> id
            _ -> nil
          end

        Events.emit_policy_denied(%{action: action, user_id: user_id})
        error
    end
  end

  object :organization do
    action :create do
      allow role: :owner
      allow role: :admin
    end

    action :read do
      allow role: :owner
      allow role: :admin
      allow role: :member
    end

    action :update do
      allow role: :owner
      allow role: :admin
    end

    action :delete do
      allow role: :owner
      allow role: :admin
    end
  end

  object :project do
    action :create do
      allow org_role: :owner
      allow org_role: :admin
      allow org_role: :member
    end

    action :read do
      allow org_role: :owner
      allow org_role: :admin
      allow org_role: :member
      allow project_role: :viewer
    end

    action :update do
      allow org_role: :owner
      allow org_role: :admin
      allow project_role: :admin
    end

    action :delete do
      allow org_role: :owner
      allow org_role: :admin
      allow project_role: :admin
    end
  end

  object :project_membership do
    action :create do
      allow org_role: :owner
      allow org_role: :admin
      allow project_role: :admin
    end

    action :read do
      allow org_role: :owner
      allow org_role: :admin
      allow org_role: :member
      allow project_role: :viewer
    end

    action :update do
      allow org_role: :owner
      allow org_role: :admin
      allow project_role: :admin
    end

    action :delete do
      allow org_role: :owner
      allow org_role: :admin
      allow project_role: :admin
    end
  end

  object :api do
    action :create do
      allow role: :owner
      allow role: :admin
      allow role: :member
      allow project_role: :editor
    end

    action :read do
      allow role: :owner
      allow role: :admin
      allow role: :member
      allow project_role: :viewer
    end

    action :update do
      allow role: :owner
      allow role: :admin
      allow role: :member
      allow project_role: :editor
    end

    action :delete do
      allow role: :owner
      allow role: :admin
      allow project_role: :admin
    end

    action :publish do
      allow role: :owner
      allow role: :admin
      allow project_role: :admin
    end

    action :unpublish do
      allow role: :owner
      allow role: :admin
      allow project_role: :admin
    end

    action :generate_tests do
      allow role: :owner
      allow role: :admin
      allow role: :member
      allow project_role: :editor
    end

    action :run_tests do
      allow role: :owner
      allow role: :admin
      allow role: :member
      allow project_role: :editor
    end

    action :generate_docs do
      allow role: :owner
      allow role: :admin
      allow role: :member
      allow project_role: :editor
    end
  end

  object :flow do
    action :create do
      allow role: :owner
      allow role: :admin
      allow role: :member
    end

    action :read do
      allow role: :owner
      allow role: :admin
      allow role: :member
    end

    action :update do
      allow role: :owner
      allow role: :admin
      allow role: :member
    end

    action :delete do
      allow role: :owner
      allow role: :admin
    end
  end

  object :page do
    action :create do
      allow role: :owner
      allow role: :admin
      allow role: :member
      allow project_role: :editor
    end

    action :read do
      allow role: :owner
      allow role: :admin
      allow role: :member
      allow project_role: :viewer
    end

    action :update do
      allow role: :owner
      allow role: :admin
      allow role: :member
      allow project_role: :editor
    end

    action :delete do
      allow role: :owner
      allow role: :admin
      allow project_role: :admin
    end
  end

  object :playground do
    action :create do
      allow role: :owner
      allow role: :admin
      allow role: :member
      allow project_role: :editor
    end

    action :read do
      allow role: :owner
      allow role: :admin
      allow role: :member
      allow project_role: :viewer
    end

    action :update do
      allow role: :owner
      allow role: :admin
      allow role: :member
      allow project_role: :editor
    end

    action :delete do
      allow role: :owner
      allow role: :admin
      allow project_role: :admin
    end

    action :execute do
      allow role: :owner
      allow role: :admin
      allow role: :member
      allow project_role: :editor
    end
  end

  object :api_key do
    action :create do
      allow role: :owner
      allow role: :admin
    end

    action :revoke do
      allow role: :owner
      allow role: :admin
    end

    action :rotate do
      allow role: :owner
      allow role: :admin
    end
  end

  object :membership do
    action :create do
      allow role: :owner
      allow role: :admin
    end

    action :read do
      allow role: :owner
      allow role: :admin
      allow role: :member
    end

    action :update do
      allow role: :owner
      allow role: :admin
    end

    action :delete do
      allow role: :owner
      allow role: :admin
    end
  end
end
