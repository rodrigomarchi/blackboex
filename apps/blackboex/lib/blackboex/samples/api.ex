defmodule Blackboex.Samples.Api do
  @moduledoc """
  API samples in the platform-wide sample catalogue.
  """

  alias Blackboex.Samples.Id

  @template_modules [
    Blackboex.Samples.ApiTemplates.ShippingQuote,
    Blackboex.Samples.ApiTemplates.BrazilianTaxCalculator,
    Blackboex.Samples.ApiTemplates.DocumentValidator,
    Blackboex.Samples.ApiTemplates.CreditScoring,
    Blackboex.Samples.ApiTemplates.PriceTable,
    Blackboex.Samples.ApiTemplates.CurrencyConverter,
    Blackboex.Samples.ApiTemplates.CompoundInterest,
    Blackboex.Samples.ApiTemplates.EligibilityChecker,
    Blackboex.Samples.ApiTemplates.GithubWebhook,
    Blackboex.Samples.ApiTemplates.SlackEventHandler,
    Blackboex.Samples.ApiTemplates.OauthCallback,
    Blackboex.Samples.ApiTemplates.FormSubmission,
    Blackboex.Samples.ApiTemplates.OpenaiStub,
    Blackboex.Samples.ApiTemplates.PaymentGateway,
    Blackboex.Samples.ApiTemplates.NotificationMock,
    Blackboex.Samples.ApiTemplates.ErrorSimulation,
    Blackboex.Samples.ApiTemplates.CrudResource,
    Blackboex.Samples.ApiTemplates.ProductCatalog,
    Blackboex.Samples.ApiTemplates.HealthCheck
  ]

  @spec list() :: [map()]
  def list do
    @template_modules
    |> Enum.map(& &1.template())
    |> Enum.with_index()
    |> Enum.map(fn {template, index} ->
      template
      |> Map.put(:kind, :api)
      |> Map.put(:sample_uuid, Id.uuid(:api, template.id))
      |> Map.put(:position, index)
    end)
  end
end
