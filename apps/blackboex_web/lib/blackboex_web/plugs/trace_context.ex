defmodule BlackboexWeb.Plugs.TraceContext do
  @moduledoc """
  Injects OpenTelemetry trace_id into Logger metadata for request correlation.

  When deployed with an OTLP-compatible collector, every log line emitted
  during a request will carry the same trace_id, enabling correlation between
  logs and distributed traces.
  """

  @behaviour Plug

  require Logger

  @impl true
  @spec init(keyword()) :: keyword()
  def init(opts), do: opts

  @impl true
  @spec call(Plug.Conn.t(), keyword()) :: Plug.Conn.t()
  def call(conn, _opts) do
    trace_id = extract_trace_id()

    if trace_id do
      Logger.metadata(trace_id: trace_id)
    end

    conn
  end

  @spec extract_trace_id() :: String.t() | nil
  defp extract_trace_id do
    span_ctx = OpenTelemetry.Tracer.current_span_ctx()

    case span_ctx do
      :undefined ->
        nil

      ctx when is_tuple(ctx) ->
        format_trace_id(elem(ctx, 1))
    end
  rescue
    _ -> nil
  end

  @spec format_trace_id(term()) :: String.t() | nil
  defp format_trace_id(trace_id) when is_integer(trace_id) and trace_id > 0 do
    trace_id
    |> :binary.encode_unsigned()
    |> Base.encode16(case: :lower)
    |> String.pad_leading(32, "0")
  end

  defp format_trace_id(_), do: nil
end
