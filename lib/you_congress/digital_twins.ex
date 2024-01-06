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

  require Logger

  @spec generate_vote(number) :: {:ok, Vote.t()} | {:error, String.t()}
  @doc """
  Generates votes for a voting.

  ## Examples

      iex> generate_votes(voting_id)
      [%Vote{}, ...]

  """
  def generate_vote(voting_id) do
    voting = Votings.get_voting!(voting_id, include: [votes: [:author]])
    topic = voting.title
    model = :"gpt-4-1106-preview"
    exclude_names = Enum.map(voting.votes, & &1.author.name)

    case AI.generate_opinion(topic, model, exclude_names) do
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
    author_data = %{
      "name" => opinion["name"],
      "bio" => opinion["bio"],
      "wikipedia_url" => url_or_nil(opinion["wikipedia_url"]),
      "twitter_username" => opinion["twitter_username"],
      "country" => opinion["country"],
      "answer_id" => answer.id
    }

    {:ok, author} = Authors.find_by_wikipedia_url_or_create(author_data)

    Votes.create_vote(%{
      opinion: opinion["opinion"],
      author_id: author.id,
      voting_id: voting_id,
      answer_id: answer.id,
      direct: true,
      twin: true
    })
  end

  @spec url_or_nil(binary) :: binary | nil
  defp url_or_nil("http" <> _ = url), do: url
  defp url_or_nil(_), do: nil
end
