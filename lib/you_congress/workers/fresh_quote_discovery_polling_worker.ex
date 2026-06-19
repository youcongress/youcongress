defmodule YouCongress.Workers.FreshQuoteDiscoveryPollingWorker do
  @moduledoc """
  Polls fresh quote discovery jobs, persists valid candidates, and enqueues matching.
  """

  use Oban.Worker,
    queue: :default,
    max_attempts: 90,
    unique: [states: [:scheduled, :available, :executing], keys: [:job_id]]

  import Ecto.Query

  require Logger

  alias YouCongress.Authors
  alias YouCongress.Opinions
  alias YouCongress.Opinions.Opinion
  alias YouCongress.Opinions.Quotes.FreshQuoteFinder
  alias YouCongress.Repo
  alias YouCongress.Workers.MatchQuoteStatementsWorker

  @stagger_interval 2

  @impl Oban.Worker
  def perform(%Oban.Job{args: %{"job_id" => job_id, "user_id" => user_id} = args} = job) do
    case FreshQuoteFinder.check_job_status(job_id) do
      {:ok, :completed, %{quotes: quotes}} ->
        quotes = List.wrap(quotes)

        candidate_results =
          quotes
          |> Enum.take(discovery_limit(args))
          |> Enum.with_index()
          |> Enum.map(fn {quote_data, index} ->
            quote_data
            |> persist_quote(user_id, index)
            |> candidate_result(index)
          end)

        result = completion_result(job_id, quotes, candidate_results)
        save_result_meta(job, result)

        Logger.info("Fresh quote discovery job #{job_id} saved #{result["saved_count"]} quote(s)")
        :ok

      {:ok, :in_progress} ->
        save_result_meta(job, %{
          "status" => "in_progress",
          "discovery_job_id" => job_id
        })

        Logger.info("Fresh quote discovery job #{job_id} still in progress")
        {:snooze, 60}

      {:error, reason} ->
        save_result_meta(job, %{
          "status" => "cancelled",
          "discovery_job_id" => job_id,
          "reason" => format_reason(reason)
        })

        Logger.error("Fresh quote discovery job #{job_id} failed: #{inspect(reason)}")
        {:cancel, reason}
    end
  end

  defp persist_quote(quote_data, user_id, index) when is_map(quote_data) do
    with {:ok, attrs} <- normalize_quote_attrs(quote_data, user_id),
         :ok <- ensure_fresh(attrs.date),
         :ok <- ensure_not_duplicate(attrs),
         {:ok, author} <- upsert_author(attrs.author),
         {:ok, %{opinion: opinion}} <-
           Opinions.create_opinion(%{
             content: attrs.quote,
             source_url: attrs.source_url,
             date: attrs.date,
             date_precision: "day",
             author_id: author.id,
             user_id: user_id,
             twin: false
           }) do
      enqueue_statement_matching(opinion.id, index)
      {:ok, opinion}
    else
      {:skip, reason} ->
        Logger.info("Skipping fresh quote candidate: #{inspect(reason)}")
        {:skip, reason}

      {:error, reason} ->
        Logger.error("Failed to persist fresh quote candidate: #{inspect(reason)}")
        {:skip, {:persistence_error, reason}}
    end
  end

  defp persist_quote(_quote_data, _user_id, _index), do: {:skip, :invalid_candidate}

  defp candidate_result({:ok, opinion}, index) do
    %{"candidate_index" => index, "outcome" => "saved", "opinion_id" => opinion.id}
  end

  defp candidate_result({:skip, reason}, index) do
    %{
      "candidate_index" => index,
      "outcome" => "skipped",
      "reason" => format_reason(reason)
    }
  end

  defp completion_result(job_id, quotes, candidate_results) do
    saved_results = Enum.filter(candidate_results, &(&1["outcome"] == "saved"))
    skipped_results = Enum.filter(candidate_results, &(&1["outcome"] == "skipped"))
    saved_count = length(saved_results)
    considered_count = length(candidate_results)

    %{
      "status" => "completed",
      "outcome" => completion_outcome(saved_count, considered_count),
      "discovery_job_id" => job_id,
      "discovered_count" => length(quotes),
      "considered_count" => considered_count,
      "not_considered_count" => max(length(quotes) - considered_count, 0),
      "saved_count" => saved_count,
      "saved_opinion_ids" => Enum.map(saved_results, & &1["opinion_id"]),
      "skipped_count" => length(skipped_results),
      "skipped_candidates" => skipped_results
    }
  end

  defp completion_outcome(_saved_count, 0), do: "no_candidates"
  defp completion_outcome(0, _considered_count), do: "no_quote_saved"
  defp completion_outcome(saved_count, saved_count), do: "all_considered_quotes_saved"
  defp completion_outcome(_saved_count, _considered_count), do: "partially_saved"

  defp save_result_meta(%Oban.Job{id: id} = job, result) when is_integer(id) do
    case Oban.update_job(job, fn persisted_job ->
           meta = Map.put(persisted_job.meta || %{}, "fresh_quote_discovery", result)
           %{meta: meta}
         end) do
      {:ok, _job} ->
        :ok

      {:error, reason} ->
        Logger.error("Failed to save fresh quote discovery result metadata: #{inspect(reason)}")
        :ok
    end
  end

  defp save_result_meta(_job, _result), do: :ok

  defp format_reason({:persistence_error, reason}) do
    "persistence_error: #{inspect(reason, limit: 20, printable_limit: 500)}"
  end

  defp format_reason(reason) when is_atom(reason), do: Atom.to_string(reason)
  defp format_reason(reason) when is_binary(reason), do: reason
  defp format_reason(reason), do: inspect(reason, limit: 20, printable_limit: 500)

  defp normalize_quote_attrs(quote_data, user_id) do
    quote = quote_data["quote"] || quote_data[:quote]
    source_url = quote_data["source_url"] || quote_data[:source_url]
    date = quote_data["date"] || quote_data[:date]
    date_precision = quote_data["date_precision"] || quote_data[:date_precision]
    author = quote_data["author"] || quote_data[:author] || %{}

    cond do
      blank?(quote) -> {:skip, :missing_quote}
      blank?(source_url) -> {:skip, :missing_source_url}
      blank?(date) -> {:skip, :missing_date}
      date_precision != "day" -> {:skip, :date_precision_not_day}
      is_nil(user_id) -> {:skip, :missing_user_id}
      true -> build_attrs(quote, source_url, date, author)
    end
  end

  defp build_attrs(quote, source_url, date, author) do
    with {:ok, parsed_date} <- parse_date(date),
         {:ok, author_attrs} <- normalize_author_attrs(author) do
      {:ok,
       %{
         quote: String.trim(quote),
         source_url: normalize_source_url(source_url),
         date: parsed_date,
         author: author_attrs
       }}
    else
      :error -> {:skip, :invalid_date}
      {:skip, _} = skip -> skip
    end
  end

  defp parse_date(%Date{} = date), do: {:ok, date}

  defp parse_date(date) when is_binary(date) do
    date
    |> String.trim()
    |> Date.from_iso8601()
  end

  defp parse_date(_date), do: :error

  defp ensure_fresh(%Date{} = date) do
    today = Date.utc_today()
    age_days = Date.diff(today, date)

    if age_days in 0..1 do
      :ok
    else
      {:skip, :outside_freshness_window}
    end
  end

  defp ensure_not_duplicate(attrs) do
    cond do
      duplicate_source_url?(attrs.source_url) ->
        {:skip, :duplicate_source_url}

      duplicate_content?(attrs.quote) ->
        {:skip, :duplicate_quote_content}

      duplicate_author_phrase?(attrs.author["name"], attrs.quote) ->
        {:skip, :duplicate_author_phrase}

      true ->
        :ok
    end
  end

  defp duplicate_source_url?(source_url) do
    Repo.exists?(
      from o in Opinion,
        where: not is_nil(o.source_url) and o.source_url == ^source_url
    )
  end

  defp duplicate_content?(quote) do
    normalized = normalize_text(quote)

    Repo.exists?(
      from o in Opinion,
        where: not is_nil(o.source_url),
        where:
          fragment(
            "trim(lower(regexp_replace(?, '[[:space:]]+', ' ', 'g'))) = ?",
            o.content,
            ^normalized
          )
    )
  end

  defp duplicate_author_phrase?(author_name, quote) when is_binary(author_name) do
    phrase = distinctive_phrase(quote)
    author_name = String.downcase(String.trim(author_name))

    if phrase in [nil, ""] or author_name == "" do
      false
    else
      Repo.exists?(
        from o in Opinion,
          join: a in assoc(o, :author),
          where: not is_nil(o.source_url),
          where: fragment("lower(?) = ?", a.name, ^author_name),
          where: fragment("position(? in lower(?)) > 0", ^phrase, o.content)
      )
    end
  end

  defp duplicate_author_phrase?(_author_name, _quote), do: false

  defp distinctive_phrase(quote) do
    quote
    |> normalize_text()
    |> String.split(" ", trim: true)
    |> Enum.take(12)
    |> Enum.join(" ")
    |> case do
      phrase when byte_size(phrase) >= 30 -> phrase
      _ -> nil
    end
  end

  defp normalize_author_attrs(author) when is_map(author) do
    name = author["name"] || author[:name]
    bio = author["bio"] || author[:bio]

    if blank?(name) do
      {:skip, :missing_author_name}
    else
      {:ok,
       %{
         "name" => String.trim(name),
         "bio" => blank_to_nil(bio),
         "wikipedia_url" =>
           normalize_wikipedia_url(author["wikipedia_url"] || author[:wikipedia_url]),
         "twitter_username" =>
           normalize_twitter(author["twitter_username"] || author[:twitter_username]),
         "twin_origin" => false,
         "public_figure" => true
       }}
    end
  end

  defp normalize_author_attrs(_author), do: {:skip, :invalid_author}

  defp upsert_author(%{"wikipedia_url" => wikipedia_url} = attrs)
       when wikipedia_url not in [nil, ""] do
    case Authors.find_by_wikipedia_url_or_create(attrs) do
      {:ok, author} -> {:ok, author}
      {:error, _} -> upsert_author_by_twitter_or_name(attrs)
    end
  end

  defp upsert_author(%{"twitter_username" => twitter_username} = attrs)
       when twitter_username not in [nil, ""] do
    upsert_author_by_twitter_or_name(attrs)
  end

  defp upsert_author(%{"name" => _name} = attrs), do: Authors.find_by_name_or_create(attrs)
  defp upsert_author(_attrs), do: {:error, :invalid_author}

  defp upsert_author_by_twitter_or_name(%{"twitter_username" => twitter_username} = attrs)
       when twitter_username not in [nil, ""] do
    case Authors.find_by_twitter_username_or_create(attrs) do
      {:ok, author} -> {:ok, author}
      {:error, _} -> Authors.find_by_name_or_create(attrs)
    end
  end

  defp upsert_author_by_twitter_or_name(%{"name" => _name} = attrs) do
    Authors.find_by_name_or_create(attrs)
  end

  defp upsert_author_by_twitter_or_name(_attrs), do: {:error, :invalid_author}

  defp enqueue_statement_matching(opinion_id, index) do
    %{"opinion_id" => opinion_id}
    |> MatchQuoteStatementsWorker.new(schedule_in: index * @stagger_interval)
    |> Oban.insert()
  end

  defp discovery_limit(args) when is_map(args) do
    case Map.get(args, "limit") || Map.get(args, :limit) do
      limit when is_integer(limit) and limit > 0 -> min(limit, 1)
      _ -> 1
    end
  end

  defp discovery_limit(_args), do: 1

  defp normalize_source_url(url) when is_binary(url), do: String.trim(url)
  defp normalize_source_url(url), do: url

  defp normalize_wikipedia_url(nil), do: nil
  defp normalize_wikipedia_url(""), do: nil

  defp normalize_wikipedia_url(url) when is_binary(url) do
    url
    |> String.trim()
    |> String.replace(~r/https?:\/\/\w+\./, "https://en.")
  end

  defp normalize_twitter(nil), do: nil
  defp normalize_twitter(""), do: nil
  defp normalize_twitter("@" <> handle), do: handle
  defp normalize_twitter("https://x.com/" <> handle), do: handle
  defp normalize_twitter("https://twitter.com/" <> handle), do: handle
  defp normalize_twitter(handle) when is_binary(handle), do: String.trim(handle)
  defp normalize_twitter(_handle), do: nil

  defp normalize_text(text) when is_binary(text) do
    text
    |> String.downcase()
    |> String.replace(~r/\s+/, " ")
    |> String.trim()
  end

  defp blank?(value) when is_binary(value), do: String.trim(value) == ""
  defp blank?(nil), do: true
  defp blank?(_value), do: false

  defp blank_to_nil(value) when is_binary(value) do
    value = String.trim(value)
    if value == "", do: nil, else: value
  end

  defp blank_to_nil(_value), do: nil
end
