defmodule YouCongress.Verifications do
  @moduledoc """
  Context for managing opinion verifications.
  """

  import Ecto.Query, warn: false
  alias YouCongress.Repo

  alias YouCongress.Accounts.User
  alias YouCongress.Accounts.Permissions
  alias YouCongress.Verifications.Verification
  alias YouCongress.Opinions.Opinion
  alias YouCongress.VerificationStatus

  @ai_statuses ~w(ai_verified ai_unverifiable disputed unverifiable unverified)a

  def list_verifications(opts \\ []) do
    query = build_query(opts)
    Repo.all(query)
  end

  def get_verification!(id), do: Repo.get!(Verification, id)

  @doc """
  Creates a human verification for an opinion by an authenticated actor.
  Always inserts a new record to preserve the full history.
  The actor identity and human model are derived here rather than trusted from attrs.
  """
  def create_verification(%User{} = actor, attrs) do
    opinion_id = attrs[:opinion_id] || attrs["opinion_id"]
    status = attrs[:status] || attrs["status"]
    opinion = if opinion_id, do: Repo.get(Opinion, opinion_id)

    with :ok <- authorize_human_verification(actor, opinion, status) do
      attrs
      |> human_attrs(actor)
      |> insert_verification(opinion_id)
    end
  end

  def create_verification(_actor, _attrs), do: {:error, :forbidden}

  @doc false
  def create_ai_verification(%User{} = actor, attrs) do
    status = attrs[:status] || attrs["status"]

    if Permissions.can_verify_opinion?(actor) and
         (status in @ai_statuses or status in Enum.map(@ai_statuses, &Atom.to_string/1)) do
      opinion_id = attrs[:opinion_id] || attrs["opinion_id"]
      insert_verification(system_attrs(attrs, actor), opinion_id)
    else
      ai_verification_error(actor, status)
    end
  end

  def create_ai_verification(_actor, _attrs), do: {:error, :forbidden}

  def update_opinion_verification_status(opinion_id) do
    cached_status =
      from(v in Verification, where: v.opinion_id == ^opinion_id)
      |> VerificationStatus.resolve()

    from(o in Opinion, where: o.id == ^opinion_id)
    |> Repo.update_all(set: [verification_status: cached_status])
  end

  defp authorize_human_verification(_actor, _opinion, status)
       when status in [:ai_verified, :ai_unverifiable, "ai_verified", "ai_unverifiable"],
       do: {:error, :invalid_human_status}

  defp authorize_human_verification(%User{} = actor, opinion, status) do
    cond do
      Permissions.can_verify_opinion?(actor) -> :ok
      status in [:endorsed, "endorsed"] and author_endorsing?(opinion, actor) -> :ok
      status in [:endorsed, "endorsed"] -> {:error, :only_author_can_endorse}
      true -> {:error, :forbidden}
    end
  end

  defp human_attrs(attrs, actor) do
    attrs
    |> Map.drop([:user_id, "user_id", :model, "model"])
    |> Map.put(:user_id, actor.id)
    |> Map.put(:model, "human")
  end

  defp system_attrs(attrs, actor) do
    attrs
    |> Map.drop([:user_id, "user_id"])
    |> Map.put(:user_id, actor.id)
  end

  defp ai_verification_error(actor, status) do
    if Permissions.can_verify_opinion?(actor) and
         status not in @ai_statuses and status not in ["ai_verified", "ai_unverifiable"],
       do: {:error, :invalid_ai_status},
       else: {:error, :forbidden}
  end

  defp insert_verification(attrs, opinion_id) do
    %Verification{}
    |> Verification.changeset(attrs)
    |> Repo.insert()
    |> tap_ok(fn _ -> update_opinion_verification_status(opinion_id) end)
  end

  defp author_endorsing?(%Opinion{} = opinion, user) do
    opinion.author_id && user.author_id && opinion.author_id == user.author_id
  end

  defp author_endorsing?(_opinion, _user), do: false

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
