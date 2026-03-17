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
