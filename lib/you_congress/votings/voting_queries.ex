defmodule YouCongress.Votings.VotingQueries do
  @moduledoc """
  Provides query functions for retrieving voting-related data from the database.
  """

  import Ecto.Query, warn: false
  alias YouCongress.Repo

  alias YouCongress.Votes.Vote

  def get_one_vote_per_voting(voting_ids, current_user \\ nil) do
    base_query =
      from(v in Vote,
        join: o in assoc(v, :opinion),
        where: v.voting_id in ^voting_ids and not is_nil(v.opinion_id),
        preload: [:author, :opinion]
      )

    query =
      if current_user do
        from([v, o] in base_query,
          order_by: [
            desc:
              fragment("CASE WHEN ? = ? THEN 1 ELSE 0 END", v.author_id, ^current_user.author_id),
            desc: o.likes_count,
            desc: v.inserted_at
          ],
          distinct: [v.voting_id],
          select: {v.voting_id, v}
        )
      else
        from([v, o] in base_query,
          order_by: [desc: o.likes_count, desc: v.inserted_at],
          distinct: [v.voting_id],
          select: {v.voting_id, v}
        )
      end

    query
    |> Repo.all()
    |> Enum.into(%{})
  end
end
