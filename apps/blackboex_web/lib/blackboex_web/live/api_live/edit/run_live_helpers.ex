defmodule BlackboexWeb.ApiLive.Edit.RunLiveHelpers do
  @moduledoc """
  Pure helper functions for the RunLive view.
  Contains request building, response validation, confirm dialog construction,
  and history item utilities.
  """

  alias Blackboex.Testing.ResponseValidator

  # ── Confirm Dialog ─────────────────────────────────────────────────────

  @spec build_confirm(String.t() | nil, map()) :: map() | nil
  def build_confirm("clear_history", _params) do
    %{
      title: "Clear request history?",
      description:
        "All saved request/response pairs will be removed. This won't affect your API code.",
      variant: :warning,
      confirm_label: "Clear",
      event: "clear_history",
      meta: %{}
    }
  end

  def build_confirm(_, _), do: nil

  # ── Request Building ───────────────────────────────────────────────────

  @spec default_test_body(map()) :: String.t()
  def default_test_body(api) do
    if api.example_request do
      Jason.encode!(api.example_request, pretty: true)
    else
      "{}"
    end
  end

  @spec build_request(map()) :: map()
  def build_request(assigns) do
    headers = build_header_list(assigns.test_headers)

    headers =
      if assigns.test_api_key != "" do
        headers ++ [{"x-api-key", assigns.test_api_key}]
      else
        headers
      end

    method = assigns.test_method |> String.downcase() |> String.to_existing_atom()

    body =
      if method in [:post, :put, :patch],
        do: assigns.test_body_json,
        else: nil

    %{method: method, url: assigns.test_url, headers: headers, body: body}
  end

  @spec build_header_list(list()) :: list()
  def build_header_list(headers) do
    headers
    |> Enum.filter(fn h -> h.key != "" end)
    |> Enum.map(fn h -> {h.key, h.value} end)
  end

  @spec headers_to_persist(map()) :: map()
  def headers_to_persist(assigns) do
    assigns.test_headers
    |> Enum.filter(fn h -> h.key != "" end)
    |> Map.new(fn h -> {h.key, h.value} end)
  end

  # ── Response Validation ────────────────────────────────────────────────

  @spec validate_response(map(), map()) :: list()
  def validate_response(response, api) do
    ResponseValidator.validate(response, api.param_schema)
  end

  # ── List Utilities ─────────────────────────────────────────────────────

  @spec update_item(list(), String.t(), atom(), any()) :: list()
  def update_item(items, id, field, value) do
    Enum.map(items, fn item ->
      if item.id == id, do: Map.put(item, field, value), else: item
    end)
  end
end
