defmodule YouCongress.Endorsements do
  @moduledoc """
  Records author endorsements that come from the author acting as themselves.
  """

  import Ecto.Query, warn: false

  alias YouCongress.Accounts.User
  alias YouCongress.OpinionStatementVerifications
  alias YouCongress.Opinions.Opinion
  alias YouCongress.OpinionsStatements.OpinionStatement
  alias YouCongress.Repo
  alias YouCongress.Verifications
  alias YouCongress.VoteVerifications
  alias YouCongress.Votes.Vote

  def endorse_opinion(%Opinion{} = opinion, user_or_id, opts \\ []) do
    with %User{} = user <- get_user(user_or_id),
         true <- author_user?(user, opinion),
         true <- Keyword.get(opts, :allow_twin, false) || opinion.twin == false do
      create_opinion_endorsement(opinion, user)

      if Keyword.get(opts, :include_existing_context, true) do
        endorse_existing_statement_relations(opinion, user)
        endorse_existing_votes(opinion, user)
      end
    end

    :ok
  end

  def endorse_opinion_statement(%OpinionStatement{} = opinion_statement, user_or_id) do
    opinion = Repo.get(Opinion, opinion_statement.opinion_id)

    with %Opinion{} = opinion <- opinion,
         %User{} = user <- get_user(user_or_id),
         true <- author_user?(user, opinion),
         true <- opinion.twin == false do
      create_opinion_statement_endorsement(opinion_statement, user)
    end

    :ok
  end

  def endorse_vote(%Vote{} = vote, user_or_id) do
    with %User{} = user <- get_user(user_or_id),
         true <- user.author_id && user.author_id == vote.author_id,
         true <- vote.direct != false,
         true <- vote.twin != true do
      create_vote_endorsement(vote, user)
    end

    :ok
  end

  def get_user(%User{} = user), do: user
  def get_user(nil), do: nil
  def get_user(user_id) when is_integer(user_id), do: Repo.get(User, user_id)
  def get_user(user_id) when is_binary(user_id), do: user_id |> String.to_integer() |> get_user()

  def author_user?(%User{author_id: author_id}, %{author_id: author_id})
      when not is_nil(author_id),
      do: true

  def author_user?(_user, _subject), do: false

  defp endorse_existing_statement_relations(%Opinion{id: opinion_id}, user) do
    from(os in OpinionStatement, where: os.opinion_id == ^opinion_id)
    |> Repo.all()
    |> Enum.each(&create_opinion_statement_endorsement(&1, user))
  end

  defp endorse_existing_votes(%Opinion{id: opinion_id, author_id: author_id}, user) do
    from(v in Vote, where: v.opinion_id == ^opinion_id and v.author_id == ^author_id)
    |> Repo.all()
    |> Enum.each(&create_vote_endorsement(&1, user))
  end

  defp create_opinion_endorsement(opinion, user) do
    Verifications.create_verification(%{
      opinion_id: opinion.id,
      user_id: user.id,
      status: :endorsed,
      comment: "Author endorsed",
      model: "human"
    })
    |> ignore_verification_result()
  end

  defp create_opinion_statement_endorsement(opinion_statement, user) do
    OpinionStatementVerifications.create_verification(%{
      opinion_statement_id: opinion_statement.id,
      user_id: user.id,
      status: :endorsed,
      comment: "Author endorsed statement relation",
      model: "human"
    })
    |> ignore_verification_result()
  end

  defp create_vote_endorsement(vote, user) do
    VoteVerifications.create_verification(%{
      vote_id: vote.id,
      opinion_id: vote.opinion_id,
      user_id: user.id,
      status: :endorsed,
      comment: "Author endorsed vote answer",
      model: "human"
    })
    |> ignore_verification_result()
  end

  defp ignore_verification_result(_result), do: :ok
end
