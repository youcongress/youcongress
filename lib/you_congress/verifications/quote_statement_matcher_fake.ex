defmodule YouCongress.Verifications.QuoteStatementMatcherFake do
  @moduledoc """
  Deterministic no-op quote-statement matcher for tests and local development.

  Submissions encode the quote id in a fake job id and polling completes with no
  matches.
  """

  @behaviour YouCongress.Verifications.QuoteStatementMatcher

  @impl true
  def submit(%{id: opinion_id}, _statements), do: {:ok, "fake:quote-statement:#{opinion_id}"}

  @impl true
  def check_job_status("fake:quote-statement:" <> _opinion_id), do: {:ok, :completed, []}
  def check_job_status(_job_id), do: {:ok, :in_progress}
end
