defmodule BlackboexWeb.Component do
  @moduledoc false

  defmacro __using__(_opts) do
    quote do
      use Phoenix.Component

      import SaladUI.Helpers

      alias Phoenix.LiveView.JS

      defp classes(input) do
        TwMerge.merge(input)
      end
    end
  end
end
