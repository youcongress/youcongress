defmodule YouCongress.Opinions.AIReplier do
  @moduledoc """
  Generate a reply from a digital twin via OpenAI's API.
  """

  @behaviour YouCongress.Opinions.AIReplier.AIReplierBehaviour

  alias YouCongress.Opinions
  alias YouCongress.Opinions.Opinion
  alias YouCongress.Votings
  alias YouCongress.Opinions.AIReplier.AIComment

  def maybe_reply(%{twin: true}), do: do_nothing()
  def maybe_reply(%{ancestry: nil}), do: do_nothing()

  def maybe_reply(opinion) do
    if Opinion.parent(opinion).twin do
      reply(opinion)
    else
      do_nothing()
    end
  end

  defp reply(opinion) do
    voting = Votings.get_voting!(opinion.voting_id)
    ancestor_and_self_ids = Opinion.path_ids(opinion)

    ancestors_and_self =
      Opinions.list_opinions(
        ids: ancestor_and_self_ids,
        preload: [:author],
        order_by: [desc: :id]
      )

    case AIComment.generate_comment(
           voting.title,
           ancestors_and_self,
           :"gpt-4o"
         ) do
      {:ok, %{reply: content, author_id: author_id}} ->
        Opinions.create_opinion(%{
          "content" => content,
          "author_id" => author_id,
          "voting_id" => opinion.voting_id,
          "ancestry" => set_ancestry(opinion),
          "twin" => true
        })

        :ok

      {:error, _} ->
        do_nothing()
    end
  end

  defp set_ancestry(%Opinion{ancestry: nil, id: id}), do: "#{id}"

  defp set_ancestry(%Opinion{ancestry: ancestry, id: id}) do
    "#{ancestry}/#{id}"
  end

  defp do_nothing(), do: :ok
end
