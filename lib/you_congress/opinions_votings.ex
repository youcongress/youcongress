defmodule YouCongress.OpinionsVotings do
  @moduledoc """
  The OpinionsVotings context for managing the many-to-many relationship between opinions and votings.
  """

  import Ecto.Query, warn: false
  alias YouCongress.Repo
  alias YouCongress.Opinions.Opinion

  @doc """
  Returns a map of {voting_id, opinion} pairs for the given voting_ids and current_user's author_id.

  ## Examples

      iex> get_opinions_by_voting_ids([1, 2, 3], current_user)
      %{1 => %Opinion{}, 2 => %Opinion{}}

  """
  def get_opinions_by_voting_ids(voting_ids, current_user)
      when is_list(voting_ids) and not is_nil(current_user) do
    from(ov in "opinions_votings",
      join: o in Opinion,
      on: ov.opinion_id == o.id,
      where: ov.voting_id in ^voting_ids and o.author_id == ^current_user.author_id,
      select: {ov.voting_id, o}
    )
    |> Repo.all()
    |> Map.new()
  end

  def get_opinions_by_voting_ids(_, nil), do: %{}
  def get_opinions_by_voting_ids([], _), do: %{}
end
