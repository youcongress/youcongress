defmodule YouCongress.Statements.SynthesisFake do
  @moduledoc """
  Deterministic, network-free implementation of
  `YouCongress.Statements.Synthesis` for dev and tests.

  `submit/2` encodes the statement in the returned job id; `check_job_status/1`
  decodes it and returns a completed synthesis citing real quote ids so the
  whole pipeline (submit -> poll -> sanitize -> persist -> render) can be
  exercised offline.
  """

  @behaviour YouCongress.Statements.Synthesis

  alias YouCongress.Opinions

  @impl true
  def submit(%{id: id}, _votes), do: {:ok, "fake:synthesis:#{id}"}

  @impl true
  def check_job_status("fake:synthesis:" <> statement_id) do
    statement_id = String.to_integer(statement_id)

    [for_ids, against_ids, middle_ids] =
      Opinions.list_opinions(statement_ids: [statement_id], only_quotes: true, limit: 3)
      |> Enum.map(& &1.id)
      |> spread_ids()

    {:ok, :completed,
     %{
       "headline" => "Fake synthesis: the debate splits over feasibility and accountability.",
       "arguments_for" => [fake_cluster("Fake argument for", for_ids)],
       "arguments_against" => [fake_cluster("Fake argument against", against_ids)],
       "middle_ground" => [fake_cluster("Fake middle ground", middle_ids)],
       "insights" => ["Fake insight one.", "Fake insight two."],
       "conclusion" => "Fake conclusion: positions differ but share a common concern.",
       "model" => "fake-llm"
     }}
  end

  def check_job_status(_job_id), do: {:ok, :in_progress}

  defp spread_ids([]), do: [[], [], []]
  defp spread_ids([id]), do: [[id], [id], [id]]
  defp spread_ids([id1, id2]), do: [[id1], [id2], [id1]]
  defp spread_ids([id1, id2, id3]), do: [[id1], [id2], [id3]]

  defp fake_cluster(title, ids) do
    %{"title" => title, "summary" => "#{title} summary.", "opinion_ids" => ids}
  end
end
