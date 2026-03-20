defmodule Blackboex.CodeGen.GenerationResult do
  @moduledoc """
  Struct representing the result of an LLM code generation.
  """

  @type t :: %__MODULE__{
          code: String.t(),
          template: atom(),
          description: String.t(),
          provider: String.t(),
          tokens_used: non_neg_integer(),
          output_tokens: non_neg_integer(),
          duration_ms: non_neg_integer(),
          method: String.t(),
          model: String.t(),
          example_request: map() | nil,
          example_response: map() | nil,
          param_schema: map() | nil
        }

  @enforce_keys [:code, :template, :description, :provider, :tokens_used]
  defstruct [
    :code,
    :template,
    :description,
    :provider,
    :tokens_used,
    :model,
    :example_request,
    :example_response,
    :param_schema,
    output_tokens: 0,
    duration_ms: 0,
    method: "POST"
  ]
end
