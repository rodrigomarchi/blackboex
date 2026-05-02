defmodule Blackboex.Samples.ApiTemplates do
  @moduledoc """
  Shared types for API sample template payload modules.
  """

  @type template :: %{
          id: String.t(),
          name: String.t(),
          description: String.t(),
          category: String.t(),
          template_type: String.t(),
          icon: String.t(),
          method: String.t(),
          files: %{
            handler: String.t(),
            helpers: String.t(),
            request_schema: String.t(),
            response_schema: String.t(),
            test: String.t(),
            readme: String.t()
          },
          param_schema: map(),
          example_request: map(),
          example_response: map(),
          validation_report: map()
        }
end
