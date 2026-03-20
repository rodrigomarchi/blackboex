defmodule Blackboex.Apis.DashboardQueries do
  @moduledoc """
  Aggregated queries for the dashboard.
  Provides org-level summaries, API listings with stats, and search.
  """

  import Ecto.Query, warn: false

  alias Blackboex.Apis.{Api, InvocationLog}
  alias Blackboex.Repo

  @spec get_org_summary(Ecto.UUID.t()) :: %{
          total_apis: non_neg_integer(),
          calls_today: non_neg_integer(),
          errors_today: non_neg_integer(),
          avg_latency_today: float() | nil
        }
  def get_org_summary(org_id) do
    today_start = DateTime.new!(Date.utc_today(), ~T[00:00:00], "Etc/UTC")

    total_apis =
      Api
      |> where([a], a.organization_id == ^org_id)
      |> select([a], count(a.id))
      |> Repo.one()

    stats =
      InvocationLog
      |> join(:inner, [l], a in Api, on: l.api_id == a.id and a.organization_id == ^org_id)
      |> where([l], l.inserted_at >= ^today_start)
      |> select([l], %{
        calls: count(l.id),
        errors: filter(count(l.id), l.status_code >= 400),
        avg_latency: avg(l.duration_ms)
      })
      |> Repo.one()

    avg_latency =
      case stats.avg_latency do
        nil -> nil
        %Decimal{} = d -> Decimal.to_float(d) |> Float.round(1)
        f when is_float(f) -> Float.round(f, 1)
      end

    %{
      total_apis: total_apis,
      calls_today: stats.calls,
      errors_today: stats.errors,
      avg_latency_today: avg_latency
    }
  end

  @spec list_apis_with_stats(Ecto.UUID.t(), keyword()) :: [
          %{
            api: Api.t(),
            calls_24h: non_neg_integer(),
            errors_24h: non_neg_integer(),
            avg_latency: float() | nil
          }
        ]
  def list_apis_with_stats(org_id, opts \\ []) do
    since = DateTime.add(DateTime.utc_now(), -86_400)
    search = Keyword.get(opts, :search)
    limit = Keyword.get(opts, :limit, 50)

    query =
      Api
      |> where([a], a.organization_id == ^org_id)
      |> maybe_search(search)
      |> join(:left, [a], l in InvocationLog, on: l.api_id == a.id and l.inserted_at >= ^since)
      |> group_by([a, l], a.id)
      |> select([a, l], %{
        api: a,
        calls_24h: count(l.id),
        errors_24h: filter(count(l.id), l.status_code >= 400),
        avg_latency: avg(l.duration_ms)
      })
      |> order_by([a], desc: a.inserted_at)
      |> limit(^limit)

    query
    |> Repo.all()
    |> Enum.map(fn row ->
      %{row | avg_latency: normalize_latency(row.avg_latency)}
    end)
  end

  @spec search_apis(Ecto.UUID.t(), String.t()) :: [Api.t()]
  def search_apis(org_id, query) do
    Api
    |> where([a], a.organization_id == ^org_id)
    |> maybe_search(query)
    |> order_by([a], desc: a.inserted_at)
    |> Repo.all()
  end

  defp maybe_search(queryable, nil), do: queryable
  defp maybe_search(queryable, ""), do: queryable

  defp maybe_search(queryable, search) when is_binary(search) do
    pattern = "%#{sanitize_like(search)}%"
    where(queryable, [a], ilike(a.name, ^pattern) or ilike(a.description, ^pattern))
  end

  defp sanitize_like(term) do
    term
    |> String.replace("\\", "\\\\")
    |> String.replace("%", "\\%")
    |> String.replace("_", "\\_")
  end

  defp normalize_latency(nil), do: nil
  defp normalize_latency(%Decimal{} = d), do: Decimal.to_float(d) |> Float.round(1)
  defp normalize_latency(f) when is_float(f), do: Float.round(f, 1)
end
