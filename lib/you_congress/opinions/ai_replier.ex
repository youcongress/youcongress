defmodule YouCongress.Opinions.AIReplier do
  @moduledoc """
  Generate a reply from a digital twin via OpenAI's API.
  """

  @behaviour YouCongress.Opinions.AIReplier.AIReplierBehaviour

  require Logger

  alias YouCongress.Opinions
  alias YouCongress.Opinions.Opinion
  alias YouCongress.Authors
  alias YouCongress.Opinions.AIReplier.AIComment

  def maybe_reply(%{twin: true}), do: do_nothing()
  def maybe_reply(%{ancestry: nil}), do: do_nothing()

  def maybe_reply(opinion) do
    parent_opinion = Opinion.parent(opinion)
    parent_author = Authors.get_author!(parent_opinion.author_id)

    if parent_author.twin_enabled do
      reply(opinion)
    else
      do_nothing()
    end
  end

  defp reply(opinion) do
    ancestor_and_self_ids = Opinion.path_ids(opinion)

    ancestors_and_self =
      Opinions.list_opinions(
        ids: ancestor_and_self_ids,
        preload: [:author, :votings],
        order_by: [desc: :id]
      )

    # Get the primary voting ID from the opinion's votings
    voting_id = Opinion.primary_voting_id(opinion)

    with {:ok, %{reply: content, author_id: author_id}} <-
           AIComment.generate_comment(ancestors_and_self, :"gpt-4o"),
         {:ok, _} <-
           Opinions.create_opinion(%{
             "content" => content,
             "author_id" => author_id,
             "voting_id" => voting_id,
             "ancestry" => set_ancestry(opinion),
             "twin" => true
           }) do
      :ok
    else
      {:error, error} ->
        Logger.error("Digital twin failed to reply #{inspect(error)}")
        do_nothing()
    end
  end

  defp set_ancestry(%Opinion{ancestry: nil, id: id}), do: "#{id}"

  defp set_ancestry(%Opinion{ancestry: ancestry, id: id}) do
    "#{ancestry}/#{id}"
  end

  defp do_nothing, do: :ok
end
