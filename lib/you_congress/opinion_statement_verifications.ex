defmodule YouCongress.OpinionStatementVerifications do
  @moduledoc """
  Context for managing opinion-statement relevance verifications.

  These verify that a quote (opinion) is exactly about the statement it is
  attached to, e.g. that a quote about a "permanent underclass" backs a
  statement about a *permanent* underclass rather than merely an underclass.
  """

  import Ecto.Query, warn: false
  alias YouCongress.Repo

  alias YouCongress.Accounts.Permissions
  alias YouCongress.Accounts.User
  alias YouCongress.OpinionStatementVerifications.OpinionStatementVerification
  alias YouCongress.OpinionsStatements.OpinionStatement
  alias YouCongress.VerificationStatus

  @ai_statuses ~w(ai_verified ai_unverifiable disputed unverifiable unverified)a

  def list_verifications(opts \\ []) do
    build_query(opts)
    |> Repo.all()
  end

  def get_verification!(id), do: Repo.get!(OpinionStatementVerification, id)

  @doc """
  Creates a human relevance verification for an authenticated actor.
  Always inserts a new record to preserve the full history.

  Progressive gate: relevance can only be verified once the quote's authenticity
  is positive. Clearing with `:unverified` is always allowed.
  """
  def create_verification(%User{} = actor, attrs) do
    opinion_statement_id = attrs[:opinion_statement_id] || attrs["opinion_statement_id"]
    status = attrs[:status] || attrs["status"]
    opinion_statement = load_opinion_statement(opinion_statement_id)

    with :ok <- authorize_human_verification(actor, opinion_statement, status),
         :ok <- check_prerequisites(opinion_statement_id, status) do
      attrs
      |> human_attrs(actor)
      |> insert_verification(opinion_statement_id)
    end
  end

  def create_verification(_actor, _attrs), do: {:error, :forbidden}

  @doc false
  def create_ai_verification(%User{} = actor, attrs) do
    status = attrs[:status] || attrs["status"]
    opinion_statement_id = attrs[:opinion_statement_id] || attrs["opinion_statement_id"]

    with :ok <- authorize_ai_verification(actor, status),
         :ok <- check_prerequisites(opinion_statement_id, status) do
      attrs
      |> system_attrs(actor)
      |> insert_verification(opinion_statement_id)
    end
  end

  def create_ai_verification(_actor, _attrs), do: {:error, :forbidden}

  defp authorize_human_verification(_actor, _opinion_statement, status)
       when status in [:ai_verified, :ai_unverifiable, "ai_verified", "ai_unverifiable"],
       do: {:error, :invalid_human_status}

  defp authorize_human_verification(%User{} = actor, opinion_statement, status) do
    cond do
      Permissions.can_verify_opinion?(actor) -> :ok
      status in [:endorsed, "endorsed"] and author_endorsing?(opinion_statement, actor) -> :ok
      status in [:endorsed, "endorsed"] -> {:error, :only_author_can_endorse}
      true -> {:error, :forbidden}
    end
  end

  defp load_opinion_statement(nil), do: nil

  defp load_opinion_statement(id) do
    OpinionStatement
    |> Repo.get(id)
    |> Repo.preload(:opinion)
  end

  defp author_endorsing?(%OpinionStatement{opinion: opinion}, %User{} = actor) do
    opinion.author_id && actor.author_id && opinion.author_id == actor.author_id
  end

  defp author_endorsing?(_opinion_statement, _actor), do: false

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

  defp authorize_ai_verification(actor, status) do
    cond do
      not Permissions.can_verify_opinion?(actor) -> {:error, :forbidden}
      ai_status?(status) -> :ok
      true -> {:error, :invalid_ai_status}
    end
  end

  defp ai_status?(status),
    do: status in @ai_statuses or status in Enum.map(@ai_statuses, &Atom.to_string/1)

  defp insert_verification(attrs, opinion_statement_id) do
    %OpinionStatementVerification{}
    |> OpinionStatementVerification.changeset(attrs)
    |> Repo.insert()
    |> tap_ok(fn _ -> update_opinion_statement_verification_status(opinion_statement_id) end)
  end

  defp check_prerequisites(_opinion_statement_id, status)
       when status in [:unverified, "unverified"],
       do: :ok

  defp check_prerequisites(nil, _status), do: :ok

  defp check_prerequisites(opinion_statement_id, _status) do
    opinion_statement =
      OpinionStatement
      |> Repo.get(opinion_statement_id)
      |> Repo.preload(:opinion)

    cond do
      # Let the changeset surface a missing/invalid link as a validation error.
      is_nil(opinion_statement) -> :ok
      VerificationStatus.positive?(opinion_statement.opinion.verification_status) -> :ok
      true -> {:error, :quote_not_verified}
    end
  end

  def update_opinion_statement_verification_status(opinion_statement_id) do
    cached_status =
      from(v in OpinionStatementVerification,
        where: v.opinion_statement_id == ^opinion_statement_id
      )
      |> VerificationStatus.resolve()

    from(os in OpinionStatement, where: os.id == ^opinion_statement_id)
    |> Repo.update_all(set: [verification_status: cached_status])
  end

  defp tap_ok({:ok, result}, fun) do
    fun.(result)
    {:ok, result}
  end

  defp tap_ok(error, _fun), do: error

  defp build_query(opts) do
    base_query = from(v in OpinionStatementVerification)

    Enum.reduce(opts, base_query, fn
      {:opinion_statement_id, id}, query when is_list(id) ->
        from q in query, where: q.opinion_statement_id in ^id

      {:opinion_statement_id, id}, query ->
        from q in query, where: q.opinion_statement_id == ^id

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
