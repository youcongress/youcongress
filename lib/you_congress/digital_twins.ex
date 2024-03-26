defmodule YouCongress.DigitalTwins do
  @moduledoc """
  Generate and create votes and authors.
  """
  alias YouCongress.Authors
  alias YouCongress.DigitalTwins.AI
  alias YouCongress.Votes
  alias YouCongress.Votes.Answers.Answer
  alias YouCongress.Votes.Vote
  alias YouCongress.Votings
  alias YouCongress.Opinions

  require Logger

  @spec generate_vote(number, binary, binary) :: {:ok, Vote.t()} | {:error, String.t()}
  @doc """
  Generates votes for a voting.

  ## Examples

      iex> generate_votes(voting_id)
      [%Vote{}, ...]

  """
  def generate_vote(voting_id, name, next_response) do
    voting = Votings.get_voting!(voting_id, preload: [votes: [:author, :answer]])
    topic = voting.title
    model = :"gpt-3.5-turbo-0125"

    case AI.generate_opinion(topic, model, next_response, name) do
      {:ok, %{opinion: vote}} ->
        case Votes.Answers.get_answer_by_response(vote["agree_rate"]) do
          %Answer{} = answer ->
            save(vote, answer, voting_id)

          nil ->
            Logger.error(
              "Failed to find answer. agree_rate: #{vote["agree_rate"]}, vote: #{inspect(vote)}"
            )

            {:error, "Failed to find answer"}
        end

      {:error, error} ->
        Logger.error("Failed to generate vote. error: #{inspect(error)}")
        {:error, "Failed to generate vote"}
    end
  end

  def save(opinion, answer, voting_id) do
    name = standarize_chat_gpt(opinion["name"])

    author_data = %{
      "name" => name,
      "bio" => opinion["bio"],
      "wikipedia_url" =>
        opinion["wikipedia_url"] |> url_or_nil() |> replace_wp_url_if_chatgpt_author(name),
      "twitter_username" => replace_twitter_if_chatgpt_author(opinion["twitter_username"], name),
      "country" => opinion["country"],
      "answer_id" => answer.id
    }

    {:ok, author} = Authors.find_by_wikipedia_url_or_create(author_data)

    if author.twin_enabled do
      {:ok, opinion} =
        Opinions.create_opinion(%{
          author_id: author.id,
          voting_id: voting_id,
          content: opinion["opinion"],
          twin: true
        })

      {:ok, vote} =
        Votes.create_vote(%{
          author_id: author.id,
          voting_id: voting_id,
          answer_id: answer.id,
          direct: true,
          twin: true,
          opinion_id: opinion.id
        })

      Opinions.update_opinion(opinion, %{vote_id: vote.id})
      {:ok, vote}
    else
      #  Set the author as twin_origin so it won't be used again and do not save
      Authors.update_author(author, %{twin_origin: true})
      Logger.warning("Author is disabled. author: #{inspect(author)}")
      {:error, :twin_disabled}
    end
  end

  defp standarize_chat_gpt("GPT-3"), do: "ChatGPT"
  defp standarize_chat_gpt("GPT-4"), do: "ChatGPT"
  defp standarize_chat_gpt("GPT-3.5"), do: "ChatGPT"
  defp standarize_chat_gpt("GPT-3.5-turbo"), do: "ChatGPT"
  defp standarize_chat_gpt(name), do: name

  defp replace_wp_url_if_chatgpt_author(_, "ChatGPT"), do: "https://en.wikipedia.org/wiki/ChatGPT"
  defp replace_wp_url_if_chatgpt_author(url, _), do: url

  defp replace_twitter_if_chatgpt_author(_, "ChatGPT"), do: nil
  defp replace_twitter_if_chatgpt_author(username, _), do: username

  @spec url_or_nil(binary) :: binary | nil
  defp url_or_nil("http" <> _ = url), do: url
  defp url_or_nil(_), do: nil
end
