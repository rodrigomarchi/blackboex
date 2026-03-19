defmodule BlackboexWeb.RateLimiterBackend do
  @moduledoc """
  Hammer ETS backend for API rate limiting.
  """
  use Hammer, backend: :ets
end
