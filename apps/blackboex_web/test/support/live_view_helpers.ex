defmodule BlackboexWeb.LiveViewHelpers do
  @moduledoc """
  Shared helpers for LiveView tests.

  Imported automatically via `ConnCase` — available in all web tests.
  """

  import Phoenix.LiveViewTest
  import ExUnit.Assertions

  @doc "Assert that a CSS selector (optionally with text) exists in the view."
  @spec assert_has(Phoenix.LiveViewTest.View.t(), String.t(), String.t() | nil) :: true
  def assert_has(view, selector, text \\ nil) do
    assert has_element?(view, selector, text)
  end

  @doc "Assert that a CSS selector (optionally with text) does NOT exist in the view."
  @spec refute_has(Phoenix.LiveViewTest.View.t(), String.t(), String.t() | nil) :: false
  def refute_has(view, selector, text \\ nil) do
    refute has_element?(view, selector, text)
  end
end
