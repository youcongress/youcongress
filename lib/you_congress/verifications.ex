defmodule YouCongress.Verifications do
  @moduledoc """
  Context for managing opinion verifications.
  """

  import Ecto.Query, warn: false
  alias YouCongress.Repo

  alias YouCongress.Accounts.Permissions
  alias YouCongress.Verifications.Verification
  alias YouCongress.Opinions.Opinion
  alias YouCongress.VerificationStatus

  def list_verifications(opts \\ []) do
    query = build_query(opts)
    Repo.all(query)
  end

  def get_verification!(id), do: Repo.get!(Verification, id)

  @doc """
  Creates a verification for an opinion by a user.
  Always inserts a new record to preserve the full history.
  Enforces that only the opinion author or a verifier can set "endorsed" status.
  """
  def create_verification(attrs) do
    opinion_id = attrs[:opinion_id] || attrs["opinion_id"]
    user_id = attrs[:user_id] || attrs["user_id"]
    status = attrs[:status] || attrs["status"]

    with :ok <- validate_endorsed(status, opinion_id, user_id) do
      %Verification{}
      |> Verification.changeset(attrs)
      |> Repo.insert()
      |> tap_ok(fn _ -> update_opinion_verification_status(opinion_id) end)
    end
  end

  def update_opinion_verification_status(opinion_id) do
    cached_status =
      from(v in Verification, where: v.opinion_id == ^opinion_id)
      |> VerificationStatus.resolve()

    from(o in Opinion, where: o.id == ^opinion_id)
    |> Repo.update_all(set: [verification_status: cached_status])
  end

  defp validate_endorsed(status, opinion_id, user_id)
       when status in [:endorsed, "endorsed"] do
    opinion = Repo.get!(Opinion, opinion_id) |> Repo.preload(:author)
    user = Repo.get!(YouCongress.Accounts.User, user_id)

    if author_endorsing?(opinion, user) || Permissions.can_verify_opinion?(user) do
      :ok
    else
      {:error, :only_author_can_endorse}
    end
  end

  defp validate_endorsed(_status, _opinion_id, _user_id), do: :ok

  defp author_endorsing?(opinion, user) do
    opinion.author_id && user.author_id && opinion.author_id == user.author_id
  end

  defp tap_ok({:ok, result}, fun) do
    fun.(result)
    {:ok, result}
  end

  defp tap_ok(error, _fun), do: error

  defp build_query(opts) do
    base_query = from(v in Verification)

    Enum.reduce(opts, base_query, fn
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
