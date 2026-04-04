defmodule Blackboex.Policy do
  @moduledoc """
  Authorization policy using LetMe DSL.
  Defines RBAC rules for organizations and memberships.
  """
  use LetMe.Policy

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

  object :api do
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

    action :publish do
      allow role: :owner
      allow role: :admin
    end

    action :unpublish do
      allow role: :owner
      allow role: :admin
    end

    action :generate_tests do
      allow role: :owner
      allow role: :admin
      allow role: :member
    end

    action :run_tests do
      allow role: :owner
      allow role: :admin
      allow role: :member
    end

    action :generate_docs do
      allow role: :owner
      allow role: :admin
      allow role: :member
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
