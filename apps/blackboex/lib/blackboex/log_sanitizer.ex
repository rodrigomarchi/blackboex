defmodule Blackboex.LogSanitizer do
  @moduledoc """
  Sanitizes log output to prevent sensitive data leakage.

  Truncates long strings and redacts patterns that look like API keys
  or bearer tokens.
  """

  @max_length 500
  @redacted "[REDACTED]"

  @api_key_patterns [
    ~r/sk-[a-zA-Z0-9\-_]{10,}/,
    ~r/Bearer\s+[a-zA-Z0-9\-._~+\/]+=*/,
    ~r/key-[a-zA-Z0-9]{20,}/,
    ~r/xoxb-[a-zA-Z0-9\-]+/,
    ~r/ghp_[a-zA-Z0-9]{36}/
  ]

  @spec sanitize(term()) :: String.t()
  def sanitize(value) when is_binary(value) do
    value
    |> truncate()
    |> redact_secrets()
  end

  def sanitize(value) do
    value
    |> inspect()
    |> sanitize()
  end

  @spec truncate(String.t()) :: String.t()
  defp truncate(str) when byte_size(str) <= @max_length, do: str

  defp truncate(str) do
    String.slice(str, 0, @max_length) <> "... [truncated, #{byte_size(str)} bytes total]"
  end

  @spec redact_secrets(String.t()) :: String.t()
  defp redact_secrets(str) do
    Enum.reduce(@api_key_patterns, str, fn pattern, acc ->
      Regex.replace(pattern, acc, @redacted)
    end)
  end
end
