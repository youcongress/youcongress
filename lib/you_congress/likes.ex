defmodule YouCongress.Likes do
  @moduledoc """
  Likes context.
  """

  import Ecto.Query, warn: false

  alias YouCongress.Repo
  alias YouCongress.Likes.Like
  alias YouCongress.Opinions.Opinion
  alias YouCongress.Accounts.User
  alias YouCongress.Votings.Voting
  alias YouCongress.Workers.UpdateOpinionLikesCountWorker

  def count(opinion_id: opinion_id) do
    from(l in Like,
      where: l.opinion_id == ^opinion_id,
      select: count(l.id)
    )
    |> Repo.one()
  end

  def like(opinion_id, %User{id: user_id}) do
    Ecto.Multi.new()
    |> Ecto.Multi.insert(:like, %Like{opinion_id: opinion_id, user_id: user_id})
    |> Oban.insert(:job, UpdateOpinionLikesCountWorker.new(%{opinion_id: opinion_id}))
    |> Repo.transaction()
    |> case do
      {:ok, %{like: like, job: _job}} -> {:ok, like}
      {:error, :like, _changeset, _changes_so_far} -> {:error, :already_liked}
      {:error, :job, _reason, _changes_so_far} -> {:error, :job_enqueue_failed}
    end
  end

  def unlike(opinion_id, %User{id: user_id}) do
    Ecto.Multi.new()
    |> Ecto.Multi.delete_all(:unlike, like_query(opinion_id, user_id))
    |> Oban.insert(:job, UpdateOpinionLikesCountWorker.new(%{opinion_id: opinion_id}))
    |> Repo.transaction()
    |> case do
      {:ok, %{unlike: {1, _}, job: _job}} -> {:ok, :unliked}
      {:ok, %{unlike: {0, _}, job: _job}} -> {:error, :already_unliked}
      {:error, :unlike, _reason, _changes_so_far} -> {:error, :unlike_failed}
      {:error, :job, _reason, _changes_so_far} -> {:error, :job_enqueue_failed}
    end
  end

  defp like_query(opinion_id, user_id) do
    from l in Like,
      where: l.opinion_id == ^opinion_id and l.user_id == ^user_id
  end

  def get_liked_opinion_ids(nil), do: []

  def get_liked_opinion_ids(user) do
    from(l in Like,
      where: l.user_id == ^user.id,
      select: l.opinion_id
    )
    |> Repo.all()
  end

  def get_liked_opinion_ids(nil, _), do: []

  def get_liked_opinion_ids(%User{id: user_id}, %Voting{} = voting) do
    from(o in Opinion,
      join: l in assoc(o, :likes),
      where: l.user_id == ^user_id and o.voting_id == ^voting.id,
      select: o.id
    )
    |> Repo.all()
  end
end
