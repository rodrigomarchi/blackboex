defmodule BlackboexWeb.Showcase.Sections.CodeViewer do
  @moduledoc false
  use BlackboexWeb, :html

  import BlackboexWeb.Showcase.Helpers
  import BlackboexWeb.Components.Editor.CodeViewer

  @code_basic ~S"""
  <div class="h-40 rounded-lg overflow-hidden">
    <.code_viewer code={@snippet} />
  </div>
  """

  @code_label ~S"""
  <div class="h-48 rounded-lg overflow-hidden">
    <.code_viewer code={@snippet} label="Generated Code" />
  </div>
  """

  @code_long ~S"""
  <div class="h-48 rounded-lg overflow-hidden">
    <.code_viewer code={@long_snippet} />
  </div>
  """

  @code_highlighting ~S"""
  <div class="h-56 rounded-lg overflow-hidden">
    <.code_viewer code={@elixir_snippet} label="Elixir" />
  </div>
  """

  @snippet """
  def handle_call({:get_api, id}, _from, state) do
    case Map.get(state.apis, id) do
      nil -> {:reply, {:error, :not_found}, state}
      api -> {:reply, {:ok, api}, state}
    end
  end\
  """

  @long_snippet """
  defmodule MyApi.Handler do
    @moduledoc "Handles incoming HTTP requests."

    alias MyApi.Request
    alias MyApi.Response

    def call(%Request{method: :get, path: "/items"} = req, opts) do
      items = Repo.all(Item)
      Response.ok(req, items)
    end

    def call(%Request{method: :get, path: "/items/" <> id} = req, opts) do
      case Repo.get(Item, id) do
        nil -> Response.not_found(req)
        item -> Response.ok(req, item)
      end
    end

    def call(%Request{method: :post, path: "/items"} = req, opts) do
      with {:ok, params} <- parse_body(req),
           {:ok, item} <- Items.create(params) do
        Response.created(req, item)
      else
        {:error, changeset} -> Response.unprocessable(req, changeset)
      end
    end

    def call(req, _opts), do: Response.not_found(req)

    defp parse_body(%Request{body: body}) do
      Jason.decode(body, keys: :atoms)
    end
  end\
  """

  @elixir_snippet """
  defmodule Payments.Processor do
    @behaviour Payments.ProcessorBehaviour

    @spec process(map()) :: {:ok, map()} | {:error, String.t()}
    def process(%{amount: amount, currency: currency} = params)
        when is_number(amount) and amount > 0 do
      params
      |> validate_currency()
      |> charge_card()
      |> record_transaction()
    end

    def process(_params), do: {:error, "invalid payment params"}

    defp validate_currency(%{currency: curr} = p) when curr in ~w(usd eur gbp),
      do: {:ok, p}

    defp validate_currency(_), do: {:error, "unsupported currency"}

    defp charge_card({:ok, params}), do: Stripe.charge(params)
    defp charge_card(err), do: err

    defp record_transaction({:ok, charge}) do
      Repo.insert(%Transaction{stripe_id: charge.id, amount: charge.amount})
    end

    defp record_transaction(err), do: err
  end\
  """

  def render(assigns) do
    assigns =
      assigns
      |> assign(:code_basic, @code_basic)
      |> assign(:code_label, @code_label)
      |> assign(:code_long, @code_long)
      |> assign(:code_highlighting, @code_highlighting)
      |> assign(:snippet, @snippet)
      |> assign(:long_snippet, @long_snippet)
      |> assign(:elixir_snippet, @elixir_snippet)

    ~H"""
    <.section_header
      title="CodeViewer"
      description="Server-rendered syntax-highlighted code viewer using Makeup and the Elixir lexer. Renders with line numbers, Monokai dark theme, and a scrollable viewport. Used throughout the app to display generated API code. This component powers the code examples in this showcase."
      module="BlackboexWeb.Components.Editor.CodeViewer"
    />
    <div class="space-y-10">
      <.showcase_block title="Basic code display" code={@code_basic}>
        <div class="h-40 rounded-lg overflow-hidden">
          <.code_viewer code={@snippet} />
        </div>
      </.showcase_block>

      <.showcase_block title="With label" code={@code_label}>
        <div class="h-48 rounded-lg overflow-hidden">
          <.code_viewer code={@snippet} label="Generated Code" />
        </div>
      </.showcase_block>

      <.showcase_block title="Long code (scrollable)" code={@code_long}>
        <div class="h-48 rounded-lg overflow-hidden">
          <.code_viewer code={@long_snippet} />
        </div>
      </.showcase_block>

      <.showcase_block title="Elixir syntax highlighting" code={@code_highlighting}>
        <div class="h-56 rounded-lg overflow-hidden">
          <.code_viewer code={@elixir_snippet} label="Elixir" />
        </div>
      </.showcase_block>
    </div>
    """
  end
end
