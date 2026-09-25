defmodule YouCongress.Verifications.AIVerifications do
  @moduledoc """
  Stores completed model output as a pending human-review proposal.

  Model output is untrusted. This module deliberately cannot update quotes,
  authors, statement links, votes, or verification status, and it does not
  cascade into another verification stage. A reviewer can compare the raw
  result with the captured subject snapshot before a separate, authorized
  workflow applies any change.
  """

  import Ecto.Query, warn: false

  require Logger

  alias YouCongress.Accounts.User
  alias YouCongress.Opinions.Opinion
  alias YouCongress.OpinionsStatements.OpinionStatement
  alias YouCongress.Repo
  alias YouCongress.Verifications.AIVerificationProposal
  alias YouCongress.Votes.Vote

  @subjects ~w(quote relevance vote)

  @doc """
  Records a completed AI result for later human review.

  The historical function name is retained for worker compatibility, but this
  function no longer cascades or mutates its subject.
  """
  @spec record_and_cascade(String.t(), integer(), map(), map()) :: :ok
  def record_and_cascade(subject, id, result, opts \\ %{})

  def record_and_cascade(subject, id, result, opts)
      when subject in @subjects and is_integer(id) and is_map(result) and is_map(opts) do
    with %User{} = actor <- system_user(),
         {:ok, snapshot} <- subject_snapshot(subject, id),
         {:ok, _proposal} <-
           create_proposal(%{
             subject: subject,
             subject_id: id,
             subject_snapshot: snapshot,
             result: result,
             request_options: stringify_keys(opts),
             model: model(result),
             requested_by_id: actor.id
           }) do
      :ok
    else
      nil ->
        Logger.warning(
          "verification_user_id not configured; skipping #{subject} proposal for ##{id}"
        )

        :ok

      {:error, :not_found} ->
        :ok

      {:error, reason} ->
        Logger.error(
          "Failed to store #{subject} AI review proposal for ##{id}: #{inspect(reason)}"
        )

        :ok
    end
  end

  def record_and_cascade(subject, id, _result, _opts) do
    Logger.warning(
      "Ignoring invalid AI verification result for #{inspect(subject)} ##{inspect(id)}"
    )

    :ok
  end

  @spec create_proposal(map()) ::
          {:ok, AIVerificationProposal.t()} | {:error, Ecto.Changeset.t()}
  def create_proposal(attrs) do
    %AIVerificationProposal{}
    |> AIVerificationProposal.changeset(attrs)
    |> Repo.insert()
  end

  @spec list_proposals(keyword()) :: [AIVerificationProposal.t()]
  def list_proposals(filters \\ []) do
    Enum.reduce(filters, AIVerificationProposal, fn
      {:subject, value}, query -> where(query, [p], p.subject == ^value)
      {:subject_id, value}, query -> where(query, [p], p.subject_id == ^value)
      {:review_status, value}, query -> where(query, [p], p.review_status == ^value)
      _, query -> query
    end)
    |> order_by([p], asc: p.inserted_at, asc: p.id)
    |> Repo.all()
  end

  defp subject_snapshot("quote", id) do
    case Repo.get(Opinion, id) do
      %Opinion{} = opinion ->
        {:ok,
         %{
           "id" => opinion.id,
           "author_id" => opinion.author_id,
           "content" => opinion.content,
           "source_url" => opinion.source_url,
           "source_text" => opinion.source_text,
           "date" => encode_date(opinion.date),
           "date_precision" => encode_value(opinion.date_precision)
         }}

      nil ->
        {:error, :not_found}
    end
  end

  defp subject_snapshot("relevance", id) do
    case Repo.get(OpinionStatement, id) do
      %OpinionStatement{} = link ->
        {:ok,
         %{
           "id" => link.id,
           "opinion_id" => link.opinion_id,
           "statement_id" => link.statement_id
         }}

      nil ->
        {:error, :not_found}
    end
  end

  defp subject_snapshot("vote", id) do
    case Repo.get(Vote, id) do
      %Vote{} = vote ->
        {:ok,
         %{
           "id" => vote.id,
           "author_id" => vote.author_id,
           "statement_id" => vote.statement_id,
           "opinion_id" => vote.opinion_id,
           "answer" => encode_value(vote.answer)
         }}

      nil ->
        {:error, :not_found}
    end
  end

  defp model(result) do
    case result["model"] || result[:model] do
      value when is_binary(value) and value != "" -> value
      _ -> "unknown"
    end
  end

  defp system_user do
    case Application.get_env(:you_congress, :verification_user_id) do
      nil -> nil
      "" -> nil
      id when is_integer(id) -> Repo.get(User, id)
      id when is_binary(id) -> parse_system_user(id)
      _ -> nil
    end
  end

  defp parse_system_user(id) do
    case Integer.parse(id) do
      {integer, ""} -> Repo.get(User, integer)
      _ -> nil
    end
  end

  defp stringify_keys(value) when is_map(value) do
    Map.new(value, fn {key, nested_value} -> {to_string(key), stringify_keys(nested_value)} end)
  end

  defp stringify_keys(value) when is_list(value), do: Enum.map(value, &stringify_keys/1)
  defp stringify_keys(value) when is_atom(value), do: Atom.to_string(value)
  defp stringify_keys(value), do: value

  defp encode_date(%Date{} = date), do: Date.to_iso8601(date)
  defp encode_date(value), do: value
  defp encode_value(nil), do: nil
  defp encode_value(value) when is_atom(value), do: Atom.to_string(value)
  defp encode_value(value), do: value
end
