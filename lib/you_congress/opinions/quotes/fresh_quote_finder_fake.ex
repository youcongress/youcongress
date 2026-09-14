defmodule YouCongress.Opinions.Quotes.FreshQuoteFinderFake do
  @moduledoc """
  Test/dev implementation for fresh quote discovery.
  """

  @behaviour YouCongress.Opinions.Quotes.FreshQuoteFinder

  alias YouCongress.Statements

  @impl true
  def find_quote(recent_quotes, opts \\ []) do
    notify({:fresh_quote_find_quote, recent_quotes, opts})

    {:ok, Application.get_env(:you_congress, :fresh_quote_finder_test_job_id, "fresh-quote-job")}
  end

  @impl true
  def check_job_status(job_id) do
    notify({:fresh_quote_check_job_status, job_id})

    Application.get_env(
      :you_congress,
      :fresh_quote_finder_test_status,
      {:ok, :completed, %{quotes: default_quotes()}}
    )
  end

  defp default_quotes do
    case Statements.list_statements(order: :id_asc) do
      [statement | _] -> [default_quote(statement)]
      [] -> []
    end
  end

  defp default_quote(statement) do
    %{
      "quote" => "I support this complete proposal: #{statement.title}",
      "source_url" => "https://example.com/fresh-ai-jobs-quote",
      "date" => Date.utc_today() |> Date.to_iso8601(),
      "date_precision" => "day",
      "author" => %{
        "name" => "Fresh Quote Author",
        "bio" => "AI policy expert",
        "wikipedia_url" => "https://en.wikipedia.org/wiki/Fresh_Quote_Author",
        "twitter_username" => "freshquoteauthor"
      },
      "validation_note" => "Fake quote for development and tests.",
      "statement_id" => statement.id,
      "all_key_ideas_covered" => true,
      "key_idea_coverage" => [
        %{"idea" => "complete statement", "evidence" => statement.title}
      ]
    }
  end

  defp notify(message) do
    case Application.get_env(:you_congress, :fresh_quote_finder_test_pid) do
      nil -> :ok
      pid -> send(pid, message)
    end
  end
end
