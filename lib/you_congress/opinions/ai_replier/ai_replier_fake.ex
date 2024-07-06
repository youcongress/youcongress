defmodule YouCongress.Opinions.AIReplier.AIReplierFake do
  @moduledoc """
  Fake reply from a digital twin via OpenAI's API.
  """

  @behaviour YouCongress.Opinions.AIReplier.AIReplierBehaviour

  alias YouCongress.Opinions.Opinion

  def maybe_reply(%{twin: true}), do: do_nothing()
  def maybe_reply(%{ancestry: nil}), do: do_nothing()

  def maybe_reply(opinion) do
    parent = Opinion.parent(opinion)

    if parent.twin do
      reply(opinion, parent)
    else
      do_nothing()
    end
  end

  defp reply(opinion, parent) do
    YouCongress.Opinions.create_opinion(%{
      "content" => Faker.Lorem.sentence(),
      "author_id" => parent.author_id,
      "voting_id" => opinion.voting_id,
      "ancestry" => set_ancestry(opinion),
      "twin" => true
    })

    :ok
  end

  defp set_ancestry(%Opinion{ancestry: nil, id: id}), do: "#{id}"

  defp set_ancestry(%Opinion{ancestry: ancestry, id: id}) do
    "#{ancestry}/#{id}"
  end

  def do_nothing, do: :ok
end
