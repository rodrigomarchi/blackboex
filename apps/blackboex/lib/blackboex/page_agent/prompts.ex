defmodule Blackboex.PageAgent.Prompts do
  @moduledoc """
  System and user prompts for the Page editor AI agent. Tailored for prose
  edits (markdown documentation, notes, posts) — distinct from the Playground
  agent (Elixir code) and the API agent (multi-file handlers).
  """

  @type run_type :: :generate | :edit

  @max_content_before 30_000

  @editor_rules """
  CONTEXT:
  You are editing a documentation/content page inside Blackboex.
  The content is written in plain MARKDOWN (CommonMark + GFM), rendered in a
  WYSIWYG editor (Tiptap). Headings, lists, quotes, code blocks, tables, links,
  and images are all supported.

  STYLE RULES:
  - Preserve the original content tone and voice whenever possible
  - Prefer clear, direct sentences; avoid unnecessary jargon
  - Use headings (#, ##, ###) to structure long sections
  - Use bullet lists when enumerating items
  - When including code, use ```` ```language ```` (for example ```` ```elixir ````)
  - Do not include front matter, raw HTML, or metadata; return clean markdown only

  REQUIRED RESPONSE FORMAT:
  Return EXACTLY one block delimited by double tildes (`~~~markdown` and `~~~`),
  containing the COMPLETE page content (not diffs/patches). This delimiter
  allows nested ```` ``` ```` code blocks without ambiguity.
  Do not write prose before the block.

  ~~~markdown
  full content here
  ~~~

  After the block, you may add one English line starting with "Summary:" that
  describes what you did in one sentence.
  """

  @system_generate """
  You are an assistant that WRITES markdown documentation pages for the
  Blackboex Pages editor. Given a user request, produce a complete,
  well-structured, idiomatic page.

  #{@editor_rules}
  """

  @system_edit """
  You are an assistant that EDITS markdown documentation pages in the
  Blackboex Pages editor. Given the current content and a change request, apply
  ONLY the requested change while preserving the existing style, tone, and
  structure.

  IMPORTANT:
  - Preserve original sections and style whenever possible
  - DO NOT rewrite parts unrelated to the request
  - Return the COMPLETE edited content (never diffs/patches)

  #{@editor_rules}
  """

  @spec system_prompt(run_type()) :: String.t()
  def system_prompt(:generate), do: @system_generate
  def system_prompt(:edit), do: @system_edit

  @doc """
  Builds the user message. Optional `history` is a list of `%{role, content}`
  maps from previous turns, oldest-first; rendered as "Conversation history:".

  For `:generate`, only the request (plus optional history) is passed. For
  `:edit`, the current content is included above the request, truncated to
  ~30k chars to avoid runaway prompts on huge pages.
  """
  @spec user_message(run_type(), String.t(), String.t() | nil,
          history: [%{role: String.t(), content: String.t()}]
        ) :: String.t()
  def user_message(run_type, message, content_before, opts \\ []) do
    history = Keyword.get(opts, :history, [])
    history_block = render_history(history)

    case run_type do
      :generate ->
        """
        #{history_block}User request:
        #{message}
        """

      :edit ->
        current = content_before |> Kernel.||("") |> truncate_content() |> sanitize_fences()

        """
        #{history_block}Current content:
        ~~~markdown
        #{current}
        ~~~

        User request:
        #{message}
        """
    end
  end

  # Defuse prompt-injection attempts where the user puts a literal fence in
  # their page content to break out of the wrapper and inject instructions.
  # Any line that starts with three (or more) tildes/backticks gets a leading
  # zero-width space inserted so the markdown parser still treats it as text
  # but the LLM no longer sees a fence terminator.
  defp sanitize_fences(content) when is_binary(content) do
    content
    |> String.replace(~r/^(~~~+)/m, "\u200B\\1")
    |> String.replace(~r/^(```+)/m, "\u200B\\1")
  end

  defp render_history([]), do: ""

  defp render_history(history) do
    lines =
      history
      |> Enum.map(fn
        %{role: "user", content: c} -> "- User: #{truncate_msg(c)}"
        %{role: "assistant", content: c} -> "- Assistant: #{truncate_msg(c)}"
        _ -> nil
      end)
      |> Enum.reject(&is_nil/1)

    case lines do
      [] -> ""
      _ -> "Conversation history (previous messages):\n" <> Enum.join(lines, "\n") <> "\n\n"
    end
  end

  defp truncate_msg(text) when is_binary(text) do
    if String.length(text) > 500, do: String.slice(text, 0, 500) <> "...", else: text
  end

  defp truncate_msg(_), do: ""

  defp truncate_content(content) when is_binary(content) do
    if String.length(content) > @max_content_before do
      String.slice(content, 0, @max_content_before) <> "\n\n[truncated by size]"
    else
      content
    end
  end
end
