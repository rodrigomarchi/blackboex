defmodule BlackboexWeb.Helpers.UrlHelpersTest do
  use ExUnit.Case, async: true

  alias BlackboexWeb.Helpers.UrlHelpers

  @moduletag :unit

  describe "org_path/1" do
    test "generates /orgs/:slug" do
      assert UrlHelpers.org_path("my-org") == "/orgs/my-org"
    end
  end

  describe "project_path/2" do
    test "generates /orgs/:slug/projects/:slug" do
      assert UrlHelpers.project_path("my-org", "my-project") ==
               "/orgs/my-org/projects/my-project"
    end
  end

  describe "api_path/3" do
    test "generates /orgs/:slug/projects/:slug/apis/:slug" do
      assert UrlHelpers.api_path("my-org", "my-project", "my-api") ==
               "/orgs/my-org/projects/my-project/apis/my-api"
    end
  end

  describe "api_edit_path/4" do
    test "generates editor path with tab" do
      assert UrlHelpers.api_edit_path("my-org", "my-project", "my-api", "chat") ==
               "/orgs/my-org/projects/my-project/apis/my-api/edit/chat"
    end

    test "generates editor path for each tab" do
      for tab <- ~w(chat validation run metrics publish info) do
        path = UrlHelpers.api_edit_path("org", "proj", "api", tab)
        assert path == "/orgs/org/projects/proj/apis/api/edit/#{tab}"
      end
    end
  end
end
