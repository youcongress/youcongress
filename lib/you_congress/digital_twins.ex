defmodule YouCongress.DigitalTwins do
  @moduledoc """
  Generate and create opinions and authors.
  """
  alias YouCongress.Authors
  alias YouCongress.DigitalTwins.AI
  alias YouCongress.Opinions
  alias YouCongress.Opinions.Answers.Answer
  alias YouCongress.Opinions.Opinion
  alias YouCongress.Votings

  require Logger

  @spec generate_opinion(number) :: {:ok, Opinion.t()} | {:error, String.t()}
  @doc """
  Generates opinions for a voting.

  ## Examples

      iex> generate_opinions(voting_id)
      [%Opinion{}, ...]

  """
  def generate_opinion(voting_id) do
    voting = Votings.get_voting!(voting_id, include: [opinions: [:author]])
    topic = voting.title
    model = :"gpt-4-1106-preview"
    exclude_names = Enum.map(voting.opinions, & &1.author.name)

    case AI.generate_opinion(topic, model, exclude_names) do
      {:ok, %{opinion: opinion}} ->
        case Opinions.Answers.get_answer_by_response(opinion["agree_rate"]) do
          %Answer{} = answer ->
            create_opinion(opinion, answer, voting_id)

          nil ->
            Logger.error(
              "Failed to find answer. agree_rate: #{opinion["agree_rate"]}, opinion: #{inspect(opinion)}"
            )

            {:error, "Failed to find answer"}
        end

      {:error, _} ->
        {:error, "Failed to generate opinion"}
    end
  end

  def create_opinion(opinion, answer, voting_id) do
    author_data = %{
      "name" => opinion["name"],
      "bio" => opinion["bio"],
      "wikipedia_url" => url_or_nil(opinion["wikipedia_url"]),
      "twitter_url" => url_or_nil(opinion["twitter_url"]),
      "country" => opinion["country"],
      "answer_id" => answer.id
    }

    {:ok, author} = Authors.find_by_wikipedia_url_or_create(author_data)

    Opinions.create_opinion(%{
      opinion: opinion["opinion"],
      author_id: author.id,
      voting_id: voting_id,
      answer_id: answer.id
    })
  end

  @spec url_or_nil(binary) :: binary | nil
  defp url_or_nil("http" <> _ = url), do: url
  defp url_or_nil(_), do: nil
end
