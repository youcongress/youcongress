defmodule YouCongress.VoteVerifications do
  @moduledoc """
  Context for managing vote-answer verifications.

  These verify that a vote's answer (for/against/abstain) is correct for the
  statement, given the opinion the vote references.

  A verification is tied to the opinion the vote pointed to at verification time.
  If the vote later references a newer opinion, prior verifications no longer
  apply and are ignored when resolving the cached status.
  """

  import Ecto.Query, warn: false
  alias YouCongress.Repo

  alias YouCongress.VoteVerifications.VoteVerification
  alias YouCongress.Votes.Vote
  alias YouCongress.Opinions.Opinion
  alias YouCongress.OpinionsStatements
  alias YouCongress.VerificationStatus

  def list_verifications(opts \\ []) do
    build_query(opts)
    |> Repo.all()
  end

  def get_verification!(id), do: Repo.get!(VoteVerification, id)

  @doc """
  Resolves the verification status for one vote in the context of a specific
  quote/opinion, without assuming the vote still points at that quote.
  """
  def status_for_vote_opinion(vote_id, opinion_id) do
    vote_id
    |> base_query_for_opinion(normalize_id(opinion_id))
    |> VerificationStatus.resolve()
  end

  @doc """
  Creates a verification for a vote by a user.
  Always inserts a new record to preserve the full history. The verification is
  stamped with the opinion the vote currently references unless an explicit
  `opinion_id` is supplied by a quote-specific verification flow.
  """
  def create_verification(attrs) do
    vote_id = attrs[:vote_id] || attrs["vote_id"]
    status = attrs[:status] || attrs["status"]
    vote = Repo.get!(Vote, vote_id)
    opinion_id = verification_opinion_id(attrs, vote)
    attrs = Map.put(attrs, :opinion_id, opinion_id)

    with :ok <- check_prerequisites(vote, opinion_id, status) do
      %VoteVerification{}
      |> VoteVerification.changeset(attrs)
      |> Repo.insert()
      |> tap_ok(fn _ -> maybe_update_vote_verification_status(vote, opinion_id) end)
    end
  end

  # Progressive gate: a vote can only be verified once both the quote's
  # authenticity and this statement's relevance are positive. A vote with no
  # sourced opinion has no pipeline, so it is not gated. Clearing is always allowed.
  defp check_prerequisites(_vote, _opinion_id, status) when status in [:unverified, "unverified"],
    do: :ok

  defp check_prerequisites(_vote, nil, _status), do: :ok

  defp check_prerequisites(%Vote{} = vote, opinion_id, _status) do
    opinion = Repo.get(Opinion, opinion_id)
    opinion_statement = OpinionsStatements.get_opinion_statement(opinion_id, vote.statement_id)

    cond do
      is_nil(opinion) ->
        {:error, :quote_not_found}

      opinion.author_id != vote.author_id ->
        {:error, :quote_author_mismatch}

      is_nil(opinion.source_url) ->
        :ok

      !VerificationStatus.positive?(opinion && opinion.verification_status) ->
        {:error, :quote_not_verified}

      !VerificationStatus.positive?(opinion_statement && opinion_statement.verification_status) ->
        {:error, :relevance_not_verified}

      true ->
        :ok
    end
  end

  @doc """
  Recomputes and caches the vote's verification_status, considering only
  verifications that match the vote's current opinion.
  """
  def update_vote_verification_status(vote_id) do
    vote = Repo.get!(Vote, vote_id)

    cached_status =
      vote_id
      |> base_query_for_opinion(vote.opinion_id)
      |> VerificationStatus.resolve()

    from(v in Vote, where: v.id == ^vote_id)
    |> Repo.update_all(set: [verification_status: cached_status])
  end

  defp verification_opinion_id(attrs, vote) do
    (attrs[:opinion_id] || attrs["opinion_id"] || vote.opinion_id)
    |> normalize_id()
  end

  defp maybe_update_vote_verification_status(
         %Vote{id: vote_id, opinion_id: opinion_id},
         opinion_id
       ),
       do: update_vote_verification_status(vote_id)

  defp maybe_update_vote_verification_status(_vote, _opinion_id), do: :ok

  defp base_query_for_opinion(vote_id, nil) do
    from(v in VoteVerification, where: v.vote_id == ^vote_id and is_nil(v.opinion_id))
  end

  defp base_query_for_opinion(vote_id, opinion_id) do
    from(v in VoteVerification, where: v.vote_id == ^vote_id and v.opinion_id == ^opinion_id)
  end

  defp tap_ok({:ok, result}, fun) do
    fun.(result)
    {:ok, result}
  end

  defp tap_ok(error, _fun), do: error

  defp normalize_id(nil), do: nil
  defp normalize_id(id) when is_integer(id), do: id
  defp normalize_id(id) when is_binary(id), do: String.to_integer(id)

  defp build_query(opts) do
    base_query = from(v in VoteVerification)

    Enum.reduce(opts, base_query, fn
      {:vote_id, id}, query when is_list(id) ->
        from q in query, where: q.vote_id in ^id

      {:vote_id, id}, query ->
        from q in query, where: q.vote_id == ^id

      {:opinion_id, opinion_id}, query when is_list(opinion_id) ->
        from q in query, where: q.opinion_id in ^opinion_id

      {:opinion_id, opinion_id}, query ->
        from q in query, where: q.opinion_id == ^opinion_id

      {:user_id, user_id}, query ->
        from q in query, where: q.user_id == ^user_id

      {:preload, preloads}, query ->
        from q in query, preload: ^preloads

      {:order_by, order}, query ->
        from q in query, order_by: ^order

      {:limit, limit}, query ->
        from q in query, limit: ^limit

      {:offset, offset}, query ->
        from q in query, offset: ^offset

      _, query ->
        query
    end)
  end
end
