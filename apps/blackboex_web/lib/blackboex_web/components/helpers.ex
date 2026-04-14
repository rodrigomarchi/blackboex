defmodule BlackboexWeb.Components.Helpers do
  @moduledoc """
  Utility functions shared across components: JS commands and i18n helpers.
  """
  use Gettext, backend: BlackboexWeb.Gettext

  alias Phoenix.LiveView.JS

  @doc "Shows an element with a fade-in transition."
  def show(js \\ %JS{}, selector) do
    JS.show(js,
      to: selector,
      time: 300,
      transition:
        {"transition-all ease-out duration-300",
         "opacity-0 translate-y-4 sm:translate-y-0 sm:scale-95",
         "opacity-100 translate-y-0 sm:scale-100"}
    )
  end

  @doc "Hides an element with a fade-out transition."
  def hide(js \\ %JS{}, selector) do
    JS.hide(js,
      to: selector,
      time: 200,
      transition:
        {"transition-all ease-in duration-200", "opacity-100 translate-y-0 sm:scale-100",
         "opacity-0 translate-y-4 sm:translate-y-0 sm:scale-95"}
    )
  end

  @doc "Translates an error message using gettext."
  def translate_error({msg, opts}) do
    if count = opts[:count] do
      Gettext.dngettext(BlackboexWeb.Gettext, "errors", msg, msg, count, opts)
    else
      Gettext.dgettext(BlackboexWeb.Gettext, "errors", msg, opts)
    end
  end

  @doc "Translates the errors for a field from a keyword list of errors."
  def translate_errors(errors, field) when is_list(errors) do
    for {^field, {msg, opts}} <- errors, do: translate_error({msg, opts})
  end

  # Scoped path helpers for org/project-aware navigation

  @doc "Builds an org-scoped path from the current scope."
  @spec org_path(map(), String.t()) :: String.t()
  def org_path(%{organization: org}, suffix \\ ""), do: "/orgs/#{org.slug}#{suffix}"

  @doc "Builds a project-scoped path from the current scope."
  @spec project_path(map(), String.t()) :: String.t()
  def project_path(%{organization: org, project: project}, suffix) when not is_nil(project),
    do: "/orgs/#{org.slug}/projects/#{project.slug}#{suffix}"

  def project_path(%{organization: _org} = scope, _suffix), do: org_path(scope, "/projects")

  @doc "Translates Backpex interface strings."
  @spec translate_backpex({String.t(), map()}) :: String.t()
  def translate_backpex({msg, opts}) do
    Gettext.dgettext(BlackboexWeb.Gettext, "backpex", msg, opts)
  end
end
