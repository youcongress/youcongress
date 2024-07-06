defmodule YouCongress.Opinions.AIReplier do
  @moduledoc """
  Generate a reply from a digital twin via OpenAI's API.
  """

  alias YouCongress.Opinions.Opinion

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
    voting = YouCongress.Votings.get_voting!(opinion.voting_id)
    ancestor_and_self_ids = YouCongress.Opinions.Opinion.path_ids(opinion)

    ancestors_and_self =
      YouCongress.Opinions.list_opinions(
        ids: ancestor_and_self_ids,
        preload: [:author],
        order_by: [desc: :id]
      )

    case YouCongress.Opinions.AIComment.generate_comment(
           voting.title,
           ancestors_and_self,
           :"gpt-4o"
         ) do
      {:ok, %{reply: content, author_id: author_id}} ->
        YouCongress.Opinions.create_opinion(%{
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
