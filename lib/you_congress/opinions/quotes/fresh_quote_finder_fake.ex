defmodule YouCongress.Opinions.Quotes.FreshQuoteFinderFake do
  @moduledoc """
  Test/dev implementation for fresh quote discovery.
  """

  @behaviour YouCongress.Opinions.Quotes.FreshQuoteFinder

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
      {:ok, :completed, %{quotes: [default_quote()]}}
    )
  end

  defp default_quote do
    %{
      "quote" =>
        "AI systems are already changing work, and public policy needs to help workers adapt while keeping deployment accountable.",
      "source_url" => "https://example.com/fresh-ai-jobs-quote",
      "date" => Date.utc_today() |> Date.to_iso8601(),
      "date_precision" => "day",
      "author" => %{
        "name" => "Fresh Quote Author",
        "bio" => "AI policy expert",
        "wikipedia_url" => "https://en.wikipedia.org/wiki/Fresh_Quote_Author",
        "twitter_username" => "freshquoteauthor"
      },
      "validation_note" => "Fake quote for development and tests."
    }
  end

  defp notify(message) do
    case Application.get_env(:you_congress, :fresh_quote_finder_test_pid) do
      nil -> :ok
      pid -> send(pid, message)
    end
  end
end
