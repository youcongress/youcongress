defmodule YouCongress.DigitalTwins.Regenerate do
  @moduledoc """
  Regenerate opinions and votes.
  """

  alias YouCongress.Accounts.Permissions
  alias YouCongress.DigitalTwins.AI
  alias YouCongress.Opinions
  alias YouCongress.Opinions.Opinion
  alias YouCongress.Likes
  alias YouCongress.Repo
  alias YouCongress.Track
  alias YouCongress.Votes
  alias YouCongress.Votes.Answers.Answer
  alias YouCongress.Votes.Vote

  def regenerate(opinion_id, current_user) do
    with :ok <- has_permission?(current_user),
         %Opinion{} = opinion <- Opinions.get_opinion(opinion_id, preload: [:author, :voting]),
         :ok <- delete_likes(opinion),
         :ok <- delete_subcomments(opinion),
         %Vote{} = vote <-
           Votes.get_by(voting_id: opinion.voting_id, author_id: opinion.author_id),
         {:ok, %{opinion: data}} <-
           AI.generate_opinion(opinion.voting.title, :"gpt-4o", nil, opinion.author.name),
         %Answer{} = answer <- Votes.Answers.get_answer_by_response(data["agree_rate"]),
         {:ok, {_opinion, vote}} =
           update_opinion_and_vote(opinion, data["opinion"], vote, answer.id) do
      Track.event("Regenerate opinion", current_user)
      {:ok, {opinion, vote}}
    else
      _ -> {:error, "Failed to regenerate opinion"}
    end
  end

  defp update_opinion_and_vote(opinion, opinion_content, vote, answer_id) do
    Repo.transaction(fn ->
      with {:ok, %Opinion{} = updated_opinion} <-
             Opinions.update_opinion(opinion, %{content: opinion_content}),
           {:ok, %Vote{} = updated_vote} <- Votes.update_vote(vote, %{answer_id: answer_id}) do
        {updated_opinion, updated_vote}
      else
        {:error, changeset} ->
          Repo.rollback(changeset)
          {:error, "Failed to update opinion and vote"}
      end
    end)
  end

  defp delete_likes(opinion) do
    case Likes.delete_likes(opinion) do
      {_, nil} -> :ok
      _ -> {:error, "Failed to delete likes"}
    end
  end

  defp delete_subcomments(opinion) do
    case Opinions.delete_subopinions(opinion) do
      {_, nil} -> :ok
      _ -> {:error, "Failed to delete comments"}
    end
  end

  defp has_permission?(current_user) do
    case Permissions.can_regenerate_opinion?(current_user) do
      true -> :ok
      false -> {:error, "You don't have permission to regenerate opinion"}
    end
  end
end
