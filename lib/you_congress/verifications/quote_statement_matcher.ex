defmodule YouCongress.Verifications.QuoteStatementMatcher do
  @moduledoc """
  Submits a sourced quote and candidate statements for matching, then polls for
  the result.

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

  @callback submit(Opinion.t(), [Statement.t()]) :: {:ok, String.t()} | {:error, term()}
  @callback check_job_status(String.t()) ::
              {:ok, :completed, [match_result()]} | {:ok, :in_progress} | {:error, term()}

  @spec submit(Opinion.t(), [Statement.t()]) :: {:ok, String.t()} | {:error, term()}
  def submit(%Opinion{} = opinion, statements) when is_list(statements) do
    implementation().submit(opinion, statements)
  end

  @spec check_job_status(String.t()) ::
          {:ok, :completed, [match_result()]} | {:ok, :in_progress} | {:error, term()}
  def check_job_status(job_id) when is_binary(job_id) do
    implementation().check_job_status(job_id)
  end

  defp implementation do
    Application.get_env(
      :you_congress,
      :quote_statement_matcher_implementation,
      YouCongress.Verifications.QuoteStatementMatcherAI
    )
  end
end
