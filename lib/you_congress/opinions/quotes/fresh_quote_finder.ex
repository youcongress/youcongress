defmodule YouCongress.Opinions.Quotes.FreshQuoteFinder do
  @moduledoc """
  Finds fresh sourced quotes about AI governance, AI safety, jobs, and society.
  """

  alias YouCongress.Opinions
  alias YouCongress.Opinions.Opinion
  alias YouCongress.Statements
  alias YouCongress.Statements.Statement

  @callback find_quote(list(map()), keyword()) :: {:ok, binary()} | {:error, any()}
  @callback check_job_status(binary()) ::
              {:ok, :completed, %{quotes: list(map())}} | {:ok, :in_progress} | {:error, any()}

  @recent_quote_limit 100
  @freshness_window_days 14

  def freshness_window_days, do: @freshness_window_days

  def find_quote(recent_quotes, opts \\ []) when is_list(recent_quotes) do
    implementation().find_quote(recent_quotes, opts)
  end

  def check_job_status(job_id) when is_binary(job_id) do
    implementation().check_job_status(job_id)
  end

  def recent_quote_inventory(limit \\ @recent_quote_limit) do
    Opinions.list_opinions(
      only_quotes: true,
      twin: false,
      order_by: [desc: :id],
      limit: limit,
      preload: :author
    )
    |> Enum.map(&serialize_inventory_quote/1)
  end

  def statement_inventory do
    Statements.list_statements(order: :id_asc)
    |> Enum.map(&serialize_inventory_statement/1)
  end

  defp serialize_inventory_quote(%Opinion{} = opinion) do
    %{
      id: opinion.id,
      quote: truncate(opinion.content, 260),
      author: opinion.author && opinion.author.name,
      source_url: opinion.source_url,
      date: Opinion.display_date(opinion)
    }
  end

  defp serialize_inventory_statement(%Statement{} = statement) do
    %{
      id: statement.id,
      title: statement.title
    }
  end

  defp truncate(nil, _limit), do: nil

  defp truncate(text, limit) when is_binary(text) do
    if String.length(text) > limit do
      String.slice(text, 0, limit) <> "..."
    else
      text
    end
  end

  defp implementation do
    Application.get_env(
      :you_congress,
      :fresh_quote_finder_implementation,
      YouCongress.Opinions.Quotes.FreshQuoteFinderAI
    )
  end
end
