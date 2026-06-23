defmodule YouCongress.VerificationStatus do
  @moduledoc """
  Shared logic for resolving the cached verification status of a subject
  (an opinion, an opinion-statement relevance link, or a vote).

  The latest human verification wins; otherwise we fall back to the latest AI
  verification. An explicit `:unverified` clears the cached status (nil).
  """

  import Ecto.Query, warn: false
  alias YouCongress.Repo

  @doc """
  Resolve the cached status from a base query that already selects the
  verification rows for a single subject. The base query's first binding is
  expected to expose `status`, `model` and `updated_at` fields.
  """
  def resolve(base_query) do
    case latest_status(base_query, model: :human) do
      nil -> map_ai_status(latest_status(base_query, model: :ai))
      :unverified -> nil
      status -> status
    end
  end

  defp latest_status(base_query, model: :human) do
    from(v in base_query,
      where: v.model == "human",
      order_by: [desc: v.updated_at, desc: v.id],
      limit: 1,
      select: v.status
    )
    |> Repo.one()
  end

  defp latest_status(base_query, model: :ai) do
    from(v in base_query,
      where: v.model != "human",
      order_by: [desc: v.updated_at, desc: v.id],
      limit: 1,
      select: v.status
    )
    |> Repo.one()
  end

  defp map_ai_status(:ai_verified), do: :ai_verified
  defp map_ai_status(:unverified), do: nil
  defp map_ai_status(nil), do: nil
  defp map_ai_status(status), do: status

  @positive [:endorsed, :verified, :ai_verified]

  @doc """
  A status counts as positive (it unlocks the next pipeline step) when it is
  `:endorsed`, `:verified` or `:ai_verified`. `nil`/unverified and the
  unverifiable/disputed states are not positive.
  """
  def positive?(status), do: to_atom(status) in @positive

  @doc """
  Combines the three pipeline statuses (quote authenticity → opinion-statement
  relevance → vote answer) into a single aggregate for display.

  The pipeline is progressive: a step is only considered once every upstream
  step is positive. A `:disputed` anywhere always wins, so a flagged problem is
  never hidden behind a green badge.

  Returns one of `:disputed`, `:endorsed`, `:verified`, `:ai_verified`,
  `:unverifiable` or `:unverified`.
  """
  def aggregate(authenticity, relevance, vote) do
    authenticity = to_atom(authenticity)
    relevance = to_atom(relevance)
    vote = to_atom(vote)

    cond do
      :disputed in [authenticity, relevance, vote] -> :disputed
      not positive?(authenticity) -> pending_label(authenticity)
      not positive?(relevance) -> pending_label(relevance)
      not positive?(vote) -> pending_label(vote)
      Enum.all?([authenticity, relevance, vote], &(&1 == :endorsed)) -> :endorsed
      Enum.any?([authenticity, relevance, vote], &(&1 == :ai_verified)) -> :ai_verified
      true -> :verified
    end
  end

  defp pending_label(status) when status in [:unverifiable, :ai_unverifiable], do: :unverifiable
  defp pending_label(_status), do: :unverified

  defp to_atom(status) when is_atom(status), do: status
  defp to_atom(status) when is_binary(status), do: String.to_existing_atom(status)
end
