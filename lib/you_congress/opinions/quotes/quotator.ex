defmodule YouCongress.Opinions.Quotes.Quotator do
  @moduledoc """
  Coordinates statement-specific quote discovery and persists validated candidates.
  """

  import Ecto.Query

  require Logger

  alias YouCongress.Authors
  alias YouCongress.Opinions
  alias YouCongress.Opinions.Opinion
  alias YouCongress.Repo
  alias YouCongress.Votes
  alias YouCongress.Statements
  alias YouCongress.Workers.QuotatorWorker

  @number_of_quotes 35
  @author_metadata_fields [
    {"bio", :bio},
    {"wikipedia_url", :wikipedia_url},
    {"twitter_username", :twitter_username}
  ]
  @type quote_item :: map()

  @callback find_quotes(
              integer(),
              binary(),
              list(binary()),
              integer(),
              non_neg_integer(),
              non_neg_integer(),
              non_neg_integer()
            ) :: {:ok, :job_started} | {:error, term()}

  @callback check_job_status(binary()) ::
              {:ok, :completed, %{quotes: list(map())}}
              | {:ok, :in_progress}
              | {:error, term()}

  @spec number_of_quotes() :: integer()
  def number_of_quotes, do: @number_of_quotes

  @doc """
  Enqueue quote discovery for a statement.

  The worker is unique per statement while a discovery run is active, so the UI
  and MCP entry points cannot accidentally start overlapping searches.
  """
  def enqueue_find_quotes(statement_id, user_id)
      when is_integer(statement_id) and is_integer(user_id) do
    case active_quote_job(statement_id) do
      nil ->
        %{statement_id: statement_id, user_id: user_id}
        |> QuotatorWorker.new()
        |> Oban.insert()

      %Oban.Job{} = job ->
        {:ok, %{job | conflict?: true}}
    end
  end

  @doc "Returns whether any quote discovery or polling job is active."
  def find_quotes_in_progress?(statement_id) when is_integer(statement_id) do
    not is_nil(active_quote_job(statement_id))
  end

  defp active_quote_job(statement_id) do
    worker_names = [
      "YouCongress.Workers.QuotatorWorker",
      "YouCongress.Workers.QuotatorPollingWorker"
    ]

    from(j in Oban.Job,
      where: j.worker in ^worker_names,
      where: fragment("?->>'statement_id' = ?", j.args, ^to_string(statement_id)),
      where: j.state in ["scheduled", "available", "executing", "retryable"],
      order_by: [desc: j.id],
      limit: 1
    )
    |> Repo.one()
  end

  def check_job_status(job_id) when is_binary(job_id) do
    implementation().check_job_status(job_id)
  end

  @doc """
  Find and save quotes for the given statement.
  """
  @spec find_and_save_quotes(
          integer(),
          list(binary()),
          integer(),
          integer(),
          integer(),
          integer()
        ) ::
          {:ok, :job_started} | {:error, any()}
  def find_and_save_quotes(
        statement_id,
        exclude_existent_names,
        user_id,
        max_remaining_llm_calls,
        max_remaining_quotes,
        total_quotes_added \\ 0
      ) do
    statement = Statements.get_statement!(statement_id)

    case implementation().find_quotes(
           statement.id,
           statement.title,
           exclude_existent_names,
           user_id,
           max_remaining_llm_calls,
           max_remaining_quotes,
           total_quotes_added
         ) do
      {:ok, :job_started} ->
        {:ok, :job_started}

      {:error, reason} ->
        Logger.error("Failed to find quotes: #{inspect(reason)}")
        {:error, reason}
    end
  end

  @doc """
  Save a list of quotes from a background job.
  """
  def save_quotes_from_job(args), do: save_quotes(args)

  # Save a list of quotes for the given statement.
  #
  # Expects a map with keys:
  #   - :statement_id (integer)
  #   - :quotes (list of quote maps)
  defp save_quotes(%{statement_id: statement_id, quotes: quotes, user_id: user_id})
       when is_integer(statement_id) and is_list(quotes) do
    saved_count =
      Enum.map(quotes, fn quote_data ->
        persist_quote(statement_id, quote_data, user_id)
      end)
      |> Enum.filter(&(&1 == :ok))
      |> length()

    Logger.info("Saved #{saved_count} quotes for statement #{statement_id}")

    {:ok, saved_count}
  end

  defp persist_quote(statement_id, quote_data, user_id) do
    with {:ok, attrs} <- normalize_quote_attrs(quote_data),
         :ok <- ensure_not_duplicate(attrs),
         {:ok, author} <- upsert_author(attrs.author) do
      Repo.transaction(fn ->
        with :ok <- ensure_author_has_no_vote(statement_id, author.id),
             {:ok, %{opinion: opinion}} <- create_opinion(attrs, author.id, user_id),
             :ok <- associate_opinion_with_statement(opinion, statement_id, user_id),
             {:ok, _vote} <- create_vote(statement_id, author.id, opinion.id, attrs.answer) do
          Logger.info("Persisted quote: #{attrs.quote}")
          :ok
        else
          error -> Repo.rollback(error)
        end
      end)
      |> case do
        {:ok, :ok} -> :ok
        {:error, reason} -> log_skipped_quote(reason)
      end
    else
      {:skip, reason} -> log_skipped_quote(reason)
      {:error, reason} -> log_failed_quote(reason)
    end
  end

  defp normalize_quote_attrs(quote_data) when is_map(quote_data) do
    quote = quote_data["quote"] || quote_data[:quote]
    source_url = quote_data["source_url"] || quote_data[:source_url]
    date = quote_data["date"] || quote_data[:date]
    date_precision = quote_data["date_precision"] || quote_data[:date_precision]
    author = quote_data["author"] || quote_data[:author]
    agree_rate = quote_data["agree_rate"] || quote_data[:agree_rate]

    with :ok <- require_string(quote, :missing_quote),
         :ok <- require_string(source_url, :missing_source_url),
         :ok <- validate_date(date, date_precision),
         :ok <- ensure_current_year(date),
         {:ok, author} <- normalize_candidate_author(author),
         {:ok, answer} <- map_agree_rate_to_answer(agree_rate) do
      {:ok,
       %{
         quote: String.trim(quote),
         source_url: String.trim(source_url),
         date: String.trim(date),
         date_precision: date_precision,
         author: author,
         answer: answer
       }}
    end
  end

  defp normalize_quote_attrs(_quote_data), do: {:skip, :invalid_quote}

  defp normalize_candidate_author(author) when is_map(author) do
    name = author["name"] || author[:name]

    with :ok <- require_string(name, :missing_author_name) do
      {:ok,
       %{
         "name" => String.trim(name),
         "bio" => blank_to_nil(author["bio"] || author[:bio]),
         "wikipedia_url" =>
           normalize_wikipedia_url(author["wikipedia_url"] || author[:wikipedia_url]),
         "twitter_username" =>
           normalize_twitter(author["twitter_username"] || author[:twitter_username]),
         "twin_origin" => false,
         "public_figure" => true
       }}
    end
  end

  defp normalize_candidate_author(_author), do: {:skip, :invalid_author}

  defp require_string(value, reason) when is_binary(value) do
    if String.trim(value) == "", do: {:skip, reason}, else: :ok
  end

  defp require_string(_value, reason), do: {:skip, reason}

  defp validate_date(date, precision) when precision in ["day", "month", "year"] do
    valid? =
      case precision do
        "day" ->
          is_binary(date) and match?({:ok, _}, Date.from_iso8601(date))

        "month" ->
          is_binary(date) and match?({:ok, _}, Date.from_iso8601(date <> "-01"))

        "year" ->
          is_binary(date) and match?({:ok, _}, Date.from_iso8601(date <> "-01-01"))
      end

    if valid?, do: :ok, else: {:skip, :invalid_date}
  end

  defp validate_date(_date, _precision), do: {:skip, :invalid_date_precision}

  defp ensure_current_year(date) do
    current_year = Date.utc_today().year

    case Integer.parse(String.slice(date, 0, 4)) do
      {^current_year, ""} -> :ok
      _ -> {:skip, :quote_not_current}
    end
  end

  defp ensure_not_duplicate(attrs) do
    normalized_quote = normalize_text(attrs.quote)

    duplicate? =
      Repo.exists?(
        from(o in Opinion,
          where: not is_nil(o.source_url),
          where:
            o.source_url == ^attrs.source_url or
              fragment(
                "trim(lower(regexp_replace(?, '[[:space:]]+', ' ', 'g'))) = ?",
                o.content,
                ^normalized_quote
              )
        )
      )

    if duplicate?, do: {:skip, :duplicate_quote}, else: :ok
  end

  defp upsert_author(%{"wikipedia_url" => wikipedia_url} = attrs)
       when wikipedia_url not in [nil, ""] do
    normalized = normalize_author_attrs(attrs)

    find_or_create_author(normalized)
  end

  defp upsert_author(%{"name" => _} = attrs) do
    normalized = normalize_author_attrs(attrs)
    find_or_create_author(normalized)
  end

  defp upsert_author(_), do: {:error, :invalid_author}

  defp find_or_create_author(attrs) do
    case find_existing_author(attrs) do
      nil -> Authors.create_author(attrs)
      author -> fill_missing_author_metadata(author, attrs)
    end
  end

  defp find_existing_author(attrs) do
    find_author_by_present(:wikipedia_url, attrs["wikipedia_url"]) ||
      find_author_by_present(:twitter_username, attrs["twitter_username"]) ||
      Authors.find_by(:name, attrs["name"])
  end

  defp find_author_by_present(_field, value) when value in [nil, ""], do: nil
  defp find_author_by_present(field, value), do: Authors.find_by(field, value)

  defp fill_missing_author_metadata(author, attrs) do
    updates =
      @author_metadata_fields
      |> Enum.reduce(%{}, fn {attr_key, field}, updates ->
        value = attrs[attr_key]

        if blank?(Map.get(author, field)) and present?(value) and
             author_metadata_available?(field, value, author.id) do
          Map.put(updates, attr_key, value)
        else
          updates
        end
      end)

    if updates == %{} do
      {:ok, author}
    else
      case Authors.update_author(author, updates) do
        {:ok, author} ->
          {:ok, author}

        {:error, changeset} ->
          Logger.warning(
            "Unable to enrich author #{author.id} from sourced quote metadata: #{inspect(changeset.errors)}"
          )

          {:ok, author}
      end
    end
  end

  defp author_metadata_available?(:wikipedia_url, value, author_id) do
    unique_author_metadata_available?(:wikipedia_url, value, author_id)
  end

  defp author_metadata_available?(:twitter_username, value, author_id) do
    unique_author_metadata_available?(:twitter_username, value, author_id)
  end

  defp author_metadata_available?(_field, _value, _author_id), do: true

  defp unique_author_metadata_available?(field, value, author_id) do
    case Authors.find_by(field, value) do
      nil -> true
      %{id: ^author_id} -> true
      _author -> false
    end
  end

  defp normalize_author_attrs(attrs) do
    %{
      "name" => attrs["name"],
      "bio" => attrs["bio"],
      "wikipedia_url" => normalize_wikipedia_url(attrs["wikipedia_url"]),
      "twitter_username" => normalize_twitter(attrs["twitter_username"]),
      "twin_origin" => false,
      "public_figure" => true
    }
  end

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

  defp map_agree_rate_to_answer("For"), do: {:ok, :for}
  defp map_agree_rate_to_answer("Against"), do: {:ok, :against}
  defp map_agree_rate_to_answer("Abstain"), do: {:ok, :abstain}
  defp map_agree_rate_to_answer(_agree_rate), do: {:skip, :unclear_vote}

  defp ensure_author_has_no_vote(statement_id, author_id) do
    case Votes.get_by(statement_id: statement_id, author_id: author_id) do
      nil -> :ok
      _vote -> {:skip, :author_already_has_vote}
    end
  end

  defp create_opinion(attrs, author_id, user_id) do
    Opinions.create_opinion(%{
      content: attrs.quote,
      source_url: attrs.source_url,
      date: attrs.date,
      date_precision: attrs.date_precision,
      author_id: author_id,
      user_id: user_id,
      twin: false
    })
  end

  defp create_vote(statement_id, author_id, opinion_id, answer) do
    Votes.create_vote(%{
      statement_id: statement_id,
      author_id: author_id,
      opinion_id: opinion_id,
      answer: answer,
      direct: true,
      twin: false
    })
  end

  defp associate_opinion_with_statement(%Opinion{} = opinion, statement_id, user_id) do
    statement = Statements.get_statement!(statement_id)

    case Opinions.add_opinion_to_statement(opinion, statement, user_id) do
      {:ok, _op} -> :ok
      {:error, :already_associated} -> :ok
      {:error, _} = error -> error
    end
  end

  defp normalize_text(text) do
    text
    |> String.downcase()
    |> String.replace(~r/\s+/, " ")
    |> String.trim()
  end

  defp blank_to_nil(value) when is_binary(value) do
    case String.trim(value) do
      "" -> nil
      value -> value
    end
  end

  defp blank_to_nil(_value), do: nil

  defp blank?(value) when is_binary(value), do: String.trim(value) == ""
  defp blank?(nil), do: true
  defp blank?(_value), do: false

  defp present?(value), do: not blank?(value)

  defp log_skipped_quote(reason) do
    Logger.info("Skipping sourced quote candidate: #{inspect(reason)}")
    :error
  end

  defp log_failed_quote(reason) do
    Logger.error("Failed to persist sourced quote: #{inspect(reason)}")
    :error
  end

  defp implementation do
    Application.get_env(
      :you_congress,
      :quotator_implementation,
      YouCongress.Opinions.Quotes.QuotatorAI
    )
  end
end
