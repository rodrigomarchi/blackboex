defmodule Blackboex.Logging do
  @moduledoc """
  Structured logging context helpers.

  Adds contextual metadata (api_id, user_id) to Logger for correlation
  in structured log output.
  """

  require Logger

  @spec with_api_context(String.t(), (-> result)) :: result when result: var
  def with_api_context(api_id, fun) when is_binary(api_id) and is_function(fun, 0) do
    previous = Logger.metadata()
    Logger.metadata(api_id: api_id)

    try do
      fun.()
    after
      Logger.metadata(previous)
    end
  end

  @spec with_user_context(term(), (-> result)) :: result when result: var
  def with_user_context(user_id, fun) when is_function(fun, 0) do
    previous = Logger.metadata()
    Logger.metadata(user_id: user_id)

    try do
      fun.()
    after
      Logger.metadata(previous)
    end
  end
end
