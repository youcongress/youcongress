defmodule YouCongress.Opinions.Quotes.Quotator do
  @moduledoc """
  Persists a batch of sourced quotes for a voting: upserts authors, creates opinions,
  creates/updates votes, associates opinions with the voting, and decreases generating_left.
  """

  require Logger

  alias YouCongress.Authors
  alias YouCongress.Opinions
  alias YouCongress.Opinions.Opinion
  alias YouCongress.Votes
  alias YouCongress.Votes.Answers
  alias YouCongress.Votings
  alias YouCongress.OpinatorWorker.GeneratingLeftServer

  @number_of_quotes 5
  @type quote_item :: map()

  @spec number_of_quotes() :: integer()
  def number_of_quotes, do: @number_of_quotes

  @doc """
  Find and save quotes for the given voting.
  """
  @spec find_and_save_quotes(integer(), list(binary()), integer()) :: {:ok, integer()} | {:error, any()}
  def find_and_save_quotes(voting_id, exclude_existent_names, user_id) do
    voting = Votings.get_voting!(voting_id)

    {:ok, _} =
      Votings.update_voting(voting, %{
        generating_left: @number_of_quotes,
        generating_total: @number_of_quotes
      })

    case implementation().find_quotes(voting.title, exclude_existent_names) do
      {:ok, %{quotes: quotes}} when is_list(quotes) ->
        {:ok, saved_count} = save_quotes(%{voting_id: voting_id, quotes: quotes, user_id: user_id})

        {:ok, _} =
          Votings.update_voting(voting, %{
            generating_left: 0,
            generating_total: 0
          })

        {:ok, saved_count}

      {:error, reason} ->
        _ = Votings.update_voting(voting, %{generating_left: 0})
        {:error, reason}
    end
  end

  # Save a list of quotes for the given voting.
  #
  # Expects a map with keys:
  #   - :voting_id (integer)
  #   - :quotes (list of quote maps)
  defp save_quotes(%{voting_id: voting_id, quotes: quotes} = args) when is_integer(voting_id) and is_list(quotes) do
    user_id = Map.get(args, :user_id)
    saved_count =
      Enum.map(quotes, fn quote ->
        persist_quote(voting_id, quote, user_id)
      end)
      |> Enum.filter(& &1 == :ok)
      |> length()

    {:ok, saved_count}
  end

  defp persist_quote(voting_id, quote, user_id) do
    try do
      with {:ok, author} <- upsert_author(quote["author"] || %{}),
           %{} = vote_attrs <- build_vote_attrs(voting_id, author, quote["agree_rate"]),
           {:ok, vote} <- create_or_update_vote(vote_attrs),
           {:ok, %{opinion: opinion}} <-
             Opinions.create_opinion(%{
               content: quote["quote"],
               source_url: quote["source_url"],
               year: parse_year(quote["year"]),
               author_id: author.id,
               twin: false,
               voting_id: voting_id
             }),
           {:ok, _} <- Votes.update_vote(vote, %{opinion_id: opinion.id, twin: false}),
           :ok <- associate_opinion_with_voting(opinion, voting_id, user_id) do
        :ok
      else
        {:error, :user_id_required} ->
          Logger.debug("Skipping association due to missing user_id")
          :error

        {:error, reason} ->
          Logger.error("Failed to persist sourced quote: #{inspect(reason)}")
          :error
      end
    after
      GeneratingLeftServer.decrease_generating_left(voting_id)
    end
  end

  defp upsert_author(%{"wikipedia_url" => wikipedia_url} = attrs) when wikipedia_url not in [nil, ""] do
    normalized = normalize_author_attrs(attrs)
    case Authors.find_by_wikipedia_url_or_create(normalized) do
      {:ok, author} -> {:ok, author}
      {:error, _} -> Authors.find_by_name_or_create(normalized)
    end
  end

  defp upsert_author(%{"name" => _} = attrs) do
    normalized = normalize_author_attrs(attrs)
    Authors.find_by_name_or_create(normalized)
  end

  defp upsert_author(_), do: {:error, :invalid_author}

  defp normalize_author_attrs(attrs) do
    %{
      "name" => attrs["name"],
      "bio" => attrs["bio"],
      "wikipedia_url" => normalize_wikipedia_url(attrs["wikipedia_url"]),
      "twitter_username" => normalize_twitter(attrs["twitter_username"]),
      "twin_origin" => false
    }
  end

  defp normalize_wikipedia_url(nil), do: nil
  defp normalize_wikipedia_url(""), do: nil
  defp normalize_wikipedia_url(url) when is_binary(url) do
    String.replace(url, ~r/https?:\/\/\w+\./, "https://en.")
  end

  defp normalize_twitter(nil), do: nil
  defp normalize_twitter(""), do: nil
  defp normalize_twitter("@" <> handle), do: handle
  defp normalize_twitter("https://x.com/" <> handle), do: handle
  defp normalize_twitter("https://twitter.com/" <> handle), do: handle
  defp normalize_twitter(handle), do: handle

  defp build_vote_attrs(voting_id, author, agree_rate) do
    answer_id = Answers.get_answer_id(agree_rate)

    %{
      voting_id: voting_id,
      author_id: author.id,
      answer_id: answer_id,
      direct: true,
      twin: false
    }
  end

  defp create_or_update_vote(attrs) do
    case Votes.get_by(voting_id: attrs.voting_id, author_id: attrs.author_id) do
      nil -> Votes.create_vote(attrs)
      vote -> Votes.update_vote(vote, attrs)
    end
  end

  defp parse_year(nil), do: nil
  defp parse_year(""), do: nil
  defp parse_year(year) when is_integer(year), do: year
  defp parse_year(year) when is_binary(year) do
    case Integer.parse(year) do
      {y, _} -> y
      :error -> nil
    end
  end

  defp associate_opinion_with_voting(%Opinion{} = opinion, voting_id, user_id) do
    voting = Votings.get_voting!(voting_id)

    case Opinions.add_opinion_to_voting(opinion, voting, user_id) do
      {:ok, _op} -> :ok
      {:error, :already_associated} -> :ok
      {:error, _} = error -> error
    end
  end

  defp implementation do
    Application.get_env(
      :you_congress,
      :quotator_implementation,
      YouCongress.Opinions.Quotes.QuotatorAI
    )
  end
end
