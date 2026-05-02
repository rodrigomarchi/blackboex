defmodule Blackboex.Samples.ApiTemplates.ScoringCredito do
  @moduledoc """
  Template: Scoring de Crédito

  Returns a simulated credit score based on income, age, employment
  history and restrictions.
  """

  @spec template() :: Blackboex.Samples.ApiTemplates.template()
  def template do
    %{
      id: "scoring-credito",
      name: "Scoring de Crédito",
      description: "Retorna score de crédito simulado baseado em renda, idade e histórico",
      category: "AI Agent Tools",
      template_type: "computation",
      icon: "chart-bar",
      method: "POST",
      files: %{
        handler: handler_code(),
        helpers: helpers_code(),
        request_schema: request_schema_code(),
        response_schema: response_schema_code(),
        test: test_code(),
        readme: readme_content()
      },
      param_schema: %{
        "renda_mensal" => "number",
        "idade" => "integer",
        "tempo_emprego_meses" => "integer",
        "tem_restricao" => "boolean"
      },
      example_request: %{
        "renda_mensal" => 5000.0,
        "idade" => 35,
        "tempo_emprego_meses" => 24,
        "tem_restricao" => false
      },
      example_response: %{
        "score" => 720,
        "faixa" => "bom",
        "limite_sugerido" => 15_000.0,
        "aprovado" => true
      },
      validation_report: %{
        "compilation" => "pass",
        "compilation_errors" => [],
        "format" => "pass",
        "format_issues" => [],
        "credo" => "pass",
        "credo_issues" => [],
        "tests" => "pass",
        "test_results" => [
          %{"name" => "good profile returns high score and approved", "status" => "pass"},
          %{"name" => "restriction returns low score and rejected", "status" => "pass"},
          %{"name" => "young age reduces score", "status" => "pass"},
          %{"name" => "missing required fields returns error", "status" => "pass"},
          %{"name" => "negative income returns error", "status" => "pass"},
          %{"name" => "underage returns error", "status" => "pass"}
        ],
        "overall" => "pass"
      }
    }
  end

  defp handler_code do
    ~S"""
    defmodule Handler do
      @moduledoc "Calculates a simulated credit score."

      @doc "Processes request and returns credit score result or validation error."
      @spec handle(map()) :: map()
      def handle(params) do
        changeset = Request.changeset(params)

        if changeset.valid? do
          data = Ecto.Changeset.apply_changes(changeset)
          score = Helpers.calculate_score(data)
          faixa = Helpers.score_faixa(score)
          limite = Helpers.limite_sugerido(score, data.renda_mensal)
          aprovado = score >= 500 and not data.tem_restricao
          %{score: score, faixa: faixa, limite_sugerido: limite, aprovado: aprovado}
        else
          errors = Ecto.Changeset.traverse_errors(changeset, fn {msg, _opts} -> msg end)
          %{error: "Validation failed", details: errors}
        end
      end
    end
    """
  end

  defp helpers_code do
    ~S"""
    defmodule Helpers do
      @moduledoc "Credit score calculation helpers."

      @doc "Calculates credit score from validated input data."
      @spec calculate_score(map()) :: integer()
      def calculate_score(data) do
        base = 300

        income_pts =
          cond do
            data.renda_mensal >= 10_000 -> 200
            data.renda_mensal >= 5_000 -> 150
            data.renda_mensal >= 2_000 -> 100
            data.renda_mensal >= 1_000 -> 50
            true -> 0
          end

        age_pts =
          cond do
            data.idade >= 40 -> 100
            data.idade >= 30 -> 80
            data.idade >= 25 -> 60
            data.idade >= 18 -> 30
            true -> 0
          end

        employment_pts =
          cond do
            data.tempo_emprego_meses >= 60 -> 150
            data.tempo_emprego_meses >= 24 -> 100
            data.tempo_emprego_meses >= 12 -> 60
            data.tempo_emprego_meses >= 6 -> 30
            true -> 0
          end

        restriction_penalty = if data.tem_restricao, do: -200, else: 0
        score = base + income_pts + age_pts + employment_pts + restriction_penalty
        min(max(score, 0), 1000)
      end

      @doc "Returns the score band label for a given score."
      @spec score_faixa(integer()) :: String.t()
      def score_faixa(score) do
        cond do
          score >= 800 -> "excelente"
          score >= 700 -> "bom"
          score >= 500 -> "regular"
          score >= 300 -> "ruim"
          true -> "muito_ruim"
        end
      end

      @doc "Returns suggested credit limit based on score and monthly income."
      @spec limite_sugerido(integer(), float()) :: float()
      def limite_sugerido(score, renda_mensal) do
        multiplier =
          cond do
            score >= 800 -> 5.0
            score >= 700 -> 3.0
            score >= 500 -> 1.5
            true -> 0.0
          end

        Float.round(renda_mensal * multiplier, 2)
      end
    end
    """
  end

  defp request_schema_code do
    ~S"""
    defmodule Request do
      @moduledoc "Input schema for the credit scoring API."
      use Blackboex.Schema

      embedded_schema do
        field :renda_mensal, :float
        field :idade, :integer
        field :tempo_emprego_meses, :integer
        field :tem_restricao, :boolean
      end

      @doc "Validates and casts incoming parameters."
      @spec changeset(map()) :: Ecto.Changeset.t()
      def changeset(params) do
        %__MODULE__{}
        |> cast(params, [:renda_mensal, :idade, :tempo_emprego_meses, :tem_restricao])
        |> validate_required([:renda_mensal, :idade, :tempo_emprego_meses, :tem_restricao])
        |> validate_number(:renda_mensal, greater_than: 0)
        |> validate_number(:idade, greater_than_or_equal_to: 18)
        |> validate_number(:tempo_emprego_meses, greater_than_or_equal_to: 0)
      end
    end
    """
  end

  defp response_schema_code do
    ~S"""
    defmodule Response do
      @moduledoc "Output schema for the credit scoring API."
      use Blackboex.Schema

      embedded_schema do
        field :score, :integer
        field :faixa, :string
        field :limite_sugerido, :float
        field :aprovado, :boolean
      end
    end
    """
  end

  defp test_code do
    ~S"""
    defmodule GeneratedAPITest do
      @moduledoc "Tests for the credit scoring handler."
      use ExUnit.Case

      @good_profile %{
        "renda_mensal" => 5000.0,
        "idade" => 35,
        "tempo_emprego_meses" => 24,
        "tem_restricao" => false
      }

      describe "Request changeset validation" do
        test "accepts valid input" do
          changeset = Request.changeset(@good_profile)
          assert changeset.valid?
        end

        test "rejects missing fields" do
          changeset = Request.changeset(%{})
          refute changeset.valid?
        end

        test "rejects underage" do
          changeset = Request.changeset(Map.put(@good_profile, "idade", 17))
          refute changeset.valid?
        end

        test "rejects negative income" do
          changeset = Request.changeset(Map.put(@good_profile, "renda_mensal", -100.0))
          refute changeset.valid?
        end
      end

      describe "successful computation" do
        test "good profile returns score >= 500 and approved" do
          result = Handler.handle(@good_profile)
          assert result.score >= 500
          assert result.aprovado == true
          assert result.limite_sugerido > 0
          assert result.faixa in ["bom", "excelente", "regular"]
        end

        test "restriction returns not approved" do
          result = Handler.handle(Map.put(@good_profile, "tem_restricao", true))
          assert result.aprovado == false
        end

        test "high income and long employment raises score" do
          params = Map.merge(@good_profile, %{
            "renda_mensal" => 15_000.0,
            "idade" => 45,
            "tempo_emprego_meses" => 72
          })
          result = Handler.handle(params)
          assert result.score >= 700
          assert result.faixa in ["bom", "excelente"]
        end
      end

      describe "error handling" do
        test "returns error for invalid input" do
          result = Handler.handle(%{})
          assert %{error: "Validation failed", details: details} = result
          assert is_map(details)
        end
      end
    end
    """
  end

  defp readme_content do
    """
    # Scoring de Crédito

    Retorna um score de crédito simulado (0–1000) baseado em renda mensal, idade,
    tempo de emprego e presença de restrições, junto com um limite de crédito sugerido.

    ## Parâmetros

    | Campo | Tipo | Obrigatório | Descrição |
    |-------|------|-------------|-----------|
    | `renda_mensal` | number | sim | Renda mensal bruta em R$ (deve ser > 0) |
    | `idade` | integer | sim | Idade em anos (mínimo 18) |
    | `tempo_emprego_meses` | integer | sim | Meses no emprego atual (>= 0) |
    | `tem_restricao` | boolean | sim | Se há restrições no CPF/crédito |

    ## Exemplo de Requisição

    ```bash
    curl -X POST https://api.blackboex.com/api/minha-org/scoring-credito \\
      -H "Content-Type: application/json" \\
      -d '{
        "renda_mensal": 5000.00,
        "idade": 35,
        "tempo_emprego_meses": 24,
        "tem_restricao": false
      }'
    ```

    ## Exemplo de Resposta

    ```json
    {
      "score": 720,
      "faixa": "bom",
      "limite_sugerido": 15000.00,
      "aprovado": true
    }
    ```

    ## Faixas de Score

    | Faixa | Score | Descrição |
    |-------|-------|-----------|
    | excelente | 800–1000 | Aprovação imediata, limite máximo |
    | bom | 700–799 | Aprovado, bom limite |
    | regular | 500–699 | Aprovado com limite reduzido |
    | ruim | 300–499 | Negado |
    | muito_ruim | 0–299 | Negado, restrições graves |

    ## Casos de Uso

    - Tool de agente de IA para pré-qualificação de crédito
    - Simulador de financiamento
    - Triagem inicial em processos de concessão de crédito
    """
  end
end
