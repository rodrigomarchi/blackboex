defmodule Blackboex.Samples.Page do
  @moduledoc """
  Page samples in the platform-wide sample catalogue.
  """

  alias Blackboex.Samples.Id

  @guide_uuid Id.uuid(:page, "formatting_guide")

  @spec list() :: [map()]
  def list do
    [
      %{
        kind: :page,
        id: "formatting_guide",
        sample_uuid: @guide_uuid,
        name: "Guia de Formatação",
        title: "[Demo] Guia de Formatação",
        description: "Markdown editor formatting guide.",
        category: "Documentation",
        position: 0,
        status: "published",
        content: """
        # Guia de Formatação do Editor

        Bem-vindo ao guia de exemplos do Blackboex. Esta página demonstra Markdown,
        listas, tabelas, blocos de código e diagramas Mermaid.

        - **Texto em negrito**
        - `código inline`
        - Listas de tarefas

        ```elixir
        Enum.map([1, 2, 3], &(&1 * 2))
        ```

        ```mermaid
        flowchart TD
          A[Request] --> B[Blackboex]
          B --> C[Response]
        ```
        """
      },
      %{
        kind: :page,
        id: "elixir_patterns",
        sample_uuid: Id.uuid(:page, "elixir_patterns"),
        parent_sample_uuid: @guide_uuid,
        name: "Padrões de Código Elixir",
        title: "[Demo] Padrões de Código Elixir",
        description: "Small Elixir reference page.",
        category: "Documentation",
        position: 1,
        status: "published",
        content: """
        # Padrões de Código Elixir

        ## Pattern Matching

        ```elixir
        with {:ok, user} <- fetch_user(id),
             :ok <- authorize(user) do
          {:ok, user}
        end
        ```
        """
      }
    ]
  end
end
