defmodule Blackboex.Samples.Playground do
  @moduledoc """
  Playground samples in the platform-wide sample catalogue.
  """

  alias Blackboex.Samples.Flow
  alias Blackboex.Samples.Id

  @spec list() :: [map()]
  def list do
    echo_flow_uuid = Flow.echo_transform().sample_uuid

    [
      %{
        kind: :playground,
        id: "enum_basics",
        sample_uuid: Id.uuid(:playground, "enum_basics"),
        name: "[Demo] Enum - Transformacoes Basicas",
        description: "Map, filter and reduce examples with Enum.",
        category: "Elixir",
        position: 0,
        code: """
        lista = [1, 2, 3, 4, 5]

        dobrados = Enum.map(lista, fn x -> x * 2 end)
        pares = Enum.filter(lista, fn x -> rem(x, 2) == 0 end)
        soma = Enum.reduce(lista, 0, fn x, acc -> x + acc end)

        IO.puts("Dobrados: \#{inspect(dobrados)}")
        IO.puts("Pares: \#{inspect(pares)}")
        IO.puts("Soma: \#{soma}")
        """
      },
      %{
        kind: :playground,
        id: "call_echo_flow",
        sample_uuid: Id.uuid(:playground, "call_echo_flow"),
        flow_sample_uuid: echo_flow_uuid,
        name: "[Demo] API - Chamando Fluxo do Projeto",
        description: "Calls the managed Echo Transform flow from playground code.",
        category: "Blackboex",
        position: 1,
        code: """
        alias Blackboex.Playgrounds.Api

        token = "{{flow:#{echo_flow_uuid}:webhook_token}}"

        case Api.call_flow(token, %{"message" => "Ola do Playground!"}) do
          {:ok, response} -> IO.inspect(response, label: "Resposta")
          {:error, reason} -> IO.puts("Erro: \#{reason}")
        end
        """
      }
    ]
  end
end
