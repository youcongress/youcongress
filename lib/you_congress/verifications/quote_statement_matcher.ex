defmodule YouCongress.Verifications.QuoteStatementMatcher do
  @moduledoc """
  Finds statements that a sourced quote can support, oppose, or abstain on.

  The implementation is swappable via the
  `:quote_statement_matcher_implementation` config key. It defaults to the
  OpenAI-backed `QuoteStatementMatcherAI`; tests can use deterministic fakes.
  """

  alias YouCongress.Opinions.Opinion
  alias YouCongress.Statements.Statement

  @type answer :: String.t()
  @type match_result :: %{
          optional(String.t()) => term(),
          optional(:statement_id) => integer(),
          optional(:answer) => answer(),
          optional(:comment) => String.t()
        }

  @callback match_statements(Opinion.t(), [Statement.t()]) ::
              {:ok, [match_result()]} | {:error, term()}

  @spec match_statements(Opinion.t(), [Statement.t()]) ::
          {:ok, [match_result()]} | {:error, term()}
  def match_statements(%Opinion{} = opinion, statements) when is_list(statements) do
    implementation().match_statements(opinion, statements)
  end

  defp implementation do
    Application.get_env(
      :you_congress,
      :quote_statement_matcher_implementation,
      YouCongress.Verifications.QuoteStatementMatcherAI
    )
  end
end
