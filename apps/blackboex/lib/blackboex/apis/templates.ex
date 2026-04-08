defmodule Blackboex.Apis.Templates do
  @moduledoc """
  Template library for pre-built API definitions.

  Each template provides all artefacts needed to create a fully working API
  without going through the LLM generation pipeline:
  - 6 source files (handler, helpers, request_schema, response_schema, test, README)
  - 4 Api schema fields (param_schema, example_request, example_response, validation_report)
  """

  @type template :: %{
          id: String.t(),
          name: String.t(),
          description: String.t(),
          category: String.t(),
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

  @category_order [
    "AI Agent Tools",
    "Webhooks",
    "Mocks",
    "Protótipos"
  ]

  @templates [
    Blackboex.Apis.Templates.CotacaoFrete.template(),
    Blackboex.Apis.Templates.CalculadoraImpostos.template(),
    Blackboex.Apis.Templates.ValidadorDocumentos.template(),
    Blackboex.Apis.Templates.ScoringCredito.template(),
    Blackboex.Apis.Templates.TabelaPrecos.template(),
    Blackboex.Apis.Templates.ConversorMoedas.template(),
    Blackboex.Apis.Templates.JurosCompostos.template(),
    Blackboex.Apis.Templates.VerificadorElegibilidade.template(),
    Blackboex.Apis.Templates.StripeWebhook.template(),
    Blackboex.Apis.Templates.GithubWebhook.template(),
    Blackboex.Apis.Templates.SlackEventHandler.template(),
    Blackboex.Apis.Templates.OauthCallback.template(),
    Blackboex.Apis.Templates.FormSubmission.template(),
    Blackboex.Apis.Templates.OpenaiStub.template(),
    Blackboex.Apis.Templates.PaymentGateway.template(),
    Blackboex.Apis.Templates.NotificationMock.template(),
    Blackboex.Apis.Templates.ErrorSimulation.template(),
    Blackboex.Apis.Templates.CrudResource.template(),
    Blackboex.Apis.Templates.ProductCatalog.template(),
    Blackboex.Apis.Templates.HealthCheck.template()
  ]

  @doc "Returns all available templates."
  @spec list() :: [template()]
  def list, do: @templates

  @doc "Returns a template by its id, or nil if not found."
  @spec get(String.t()) :: template() | nil
  def get(id) do
    Enum.find(@templates, fn t -> t.id == id end)
  end

  @doc "Returns the unique sorted list of categories present in the template library."
  @spec categories() :: [String.t()]
  def categories do
    present =
      @templates
      |> Enum.map(& &1.category)
      |> Enum.uniq()
      |> MapSet.new()

    Enum.filter(@category_order, &MapSet.member?(present, &1))
  end

  @doc "Returns templates grouped by category, in canonical category order."
  @spec list_by_category() :: [{String.t(), [template()]}]
  def list_by_category do
    grouped = Enum.group_by(@templates, & &1.category)

    @category_order
    |> Enum.filter(&Map.has_key?(grouped, &1))
    |> Enum.map(fn cat -> {cat, Map.fetch!(grouped, cat)} end)
  end
end
