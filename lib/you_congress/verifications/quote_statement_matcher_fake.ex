defmodule YouCongress.Verifications.QuoteStatementMatcherFake do
  @moduledoc """
  Deterministic no-op quote-statement matcher for tests and local development.
  """

  @behaviour YouCongress.Verifications.QuoteStatementMatcher

  @impl true
  def match_statements(_opinion, _statements), do: {:ok, []}
end
