defmodule YouCongress.Opinions.Replier.AIReplierFake do
  @moduledoc """
  Fake reply from a digital twin via OpenAI's API.
  """

  @behaviour YouCongress.Opinions.Replier.AIReplierBehaviour

  alias YouCongress.Opinions.Opinion
  alias YouCongress.Opinions
  alias Faker.Lorem

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
    Opinions.create_opinion(%{
      "content" => Lorem.sentence(),
      "author_id" => parent.author_id,
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
