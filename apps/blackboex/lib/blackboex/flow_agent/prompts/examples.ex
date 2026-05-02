defmodule Blackboex.FlowAgent.Prompts.Examples do
  @moduledoc """
  Compile-time few-shot examples injected into the FlowAgent system prompt.

  Three canonical templates are picked to cover the node-type surface the LLM
  most commonly needs:

    * `hello_world` — conditional 3-way routing (start, elixir_code, condition, end)
    * `rest_api_crud` — HTTP chaining with state interpolation
    * `all_nodes_demo` — webhook_wait + for_each + delay + sub_flow + condition

  Definitions are serialized at compile time so any change to the template
  source triggers recompilation of this module (via the compile-time module
  dependency), keeping the prompt in sync with the live templates.
  """

  alias Blackboex.Samples.FlowTemplates.{AllNodesDemo, HelloWorld, RestApiCrud}

  @examples [
    {"Exemplo 1 — hello_world (roteamento condicional 3-way)", HelloWorld.template().definition},
    {"Exemplo 2 — rest_api_crud (HTTP chaining: POST + GET)", RestApiCrud.template().definition},
    {"Exemplo 3 — all_nodes_demo (showcase de tipos avançados)",
     AllNodesDemo.template().definition}
  ]

  @serialized Enum.map(@examples, fn {label, def} ->
                {label, Jason.encode!(def, pretty: true)}
              end)

  @doc """
  Returns the pre-serialized few-shot block for inclusion in the system
  prompt. Each example is framed with a human-readable label and wrapped in
  a `~~~json ... ~~~` fence so the LLM learns the exact output format it
  must emit.
  """
  @spec few_shot_json() :: String.t()
  def few_shot_json do
    @serialized
    |> Enum.map(fn {label, json} -> "#{label}:\n~~~json\n#{json}\n~~~" end)
    |> Enum.join("\n\n")
  end
end
