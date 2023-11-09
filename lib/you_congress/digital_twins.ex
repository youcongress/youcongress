defmodule YouCongress.DigitalTwins do
  alias YouCongress.Opinions
  alias YouCongress.Opinions.Opinion
  alias YouCongress.Authors
  alias YouCongress.Votings
  alias YouCongress.DigitalTwins.AI

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
    model = :"gpt-4"
    exclude_names = Enum.map(voting.opinions, & &1.author.name)

    case AI.generate_opinion(topic, model, exclude_names) do
      {:ok, %{opinion: opinion}} ->
        author_data = %{
          "name" => opinion["name"],
          "bio" => opinion["bio"],
          "wikipedia_url" => url_or_nil(opinion["wikipedia_url"]),
          "twitter_url" => url_or_nil(opinion["twitter_url"]),
          "country" => opinion["country"]
        }

        {:ok, author} = Authors.find_by_name_or_create(author_data)

        Opinions.create_opinion(%{
          opinion: opinion["opinion"],
          author_id: author.id,
          voting_id: voting_id
        })

      {:error, _} ->
        {:error, "Failed to generate opinion"}
    end
  end

  @spec url_or_nil(binary) :: binary | nil
  defp url_or_nil("http" <> _ = url), do: url
  defp url_or_nil(_), do: nil
end
