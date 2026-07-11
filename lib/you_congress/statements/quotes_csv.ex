defmodule YouCongress.Statements.QuotesCsv do
  @moduledoc """
  Builds the CSV export of a statement's sourced quotes.

  One row per quote vote, with the latest verification of each kind — quote
  authenticity, statement relevance and vote answer — and its comment. Only the
  most recent verification per kind is exported, not the full history.

  The first two rows carry the licence notice: YouCongress annotations are
  CC BY 4.0, while quote text and author bios are third-party content that
  remains its rights holders' property.
  """

  import Ecto.Query, warn: false

  use YouCongressWeb, :verified_routes

  alias NimbleCSV.RFC4180, as: CSV

  alias YouCongress.Cache
  alias YouCongress.Opinions.Opinion
  alias YouCongress.OpinionsStatements.OpinionStatement
  alias YouCongress.OpinionStatementVerifications
  alias YouCongress.Repo
  alias YouCongress.Statements
  alias YouCongress.Statements.Statement
  alias YouCongress.VerificationStatus
  alias YouCongress.Verifications
  alias YouCongress.Votes
  alias YouCongress.VoteVerifications
  alias YouCongressWeb.SEO

  @license_rows [
    [
      "License CC BY 4.0 (https://creativecommons.org/licenses/by/4.0/): the YouCongress annotations in this file — statement titles and statement-to-quote mapping, vote labels, verification statuses, comments and dates, and the column schema. Attribution: YouCongress (https://youcongress.org)."
    ],
    [
      "Not licensed by us: quote text and author bios are third-party content reproduced as short excerpts under the right of quotation and remain the property of their respective rights holders. See each row's source_url for the original source."
    ]
  ]

  @headers [
    "statement_title",
    "statement_id",
    "statement_url",
    "opinion_id",
    "opinion_url",
    "author",
    "author_url",
    "author_bio",
    "author_x_url",
    "author_wikipedia_url",
    "quote",
    "vote",
    "quote_date",
    "quote_date_precision",
    "source_url",
    "quote_verification_status",
    "quote_verification_comment",
    "quote_verification_date",
    "relevance_verification_status",
    "relevance_verification_comment",
    "relevance_verification_date",
    "vote_verification_status",
    "vote_verification_comment",
    "vote_verification_date"
  ]

  @spec generate(Statement.t()) :: binary
  def generate(%Statement{} = statement) do
    Cache.fetch({:statement_csv, statement.id}, :timer.hours(1), fn ->
      dump([@headers | rows(statement)])
    end)
  end

  # Minimum verified quotes a statement needs to be included in the dataset export.
  @min_quotes 3

  @doc """
  CSV export of every statement's sourced quotes, all in one file.
  Same columns as `generate/1`, with one row per quote vote across all statements.
  Only statements with at least #{@min_quotes} verified quotes are included.
  """
  @spec generate_all() :: binary
  def generate_all do
    Cache.fetch(:dataset_csv, :timer.hours(1), &generate_all_uncached/0)
  end

  defp generate_all_uncached do
    rows =
      Statements.list_statements()
      |> Enum.map(&rows/1)
      |> Enum.filter(&(length(&1) >= @min_quotes))
      |> Enum.concat()

    dump([@headers | rows])
  end

  defp dump(data) do
    (@license_rows ++ data)
    |> CSV.dump_to_iodata()
    |> IO.iodata_to_binary()
  end

  defp rows(%Statement{} = statement) do
    votes =
      Votes.list_votes_with_opinion(statement.id,
        include: [:author, opinion: :author],
        source_filter: :quotes
      )
      |> filter_verified(statement.id)

    opinion_ids = Enum.map(votes, & &1.opinion_id)

    quote_verifications =
      Verifications.list_verifications(opinion_id: opinion_ids)
      |> latest_by(& &1.opinion_id)

    relevance_verifications = relevance_verifications(statement.id, opinion_ids)
    vote_verifications = vote_verifications(votes)

    Enum.map(votes, fn vote ->
      row(
        statement,
        vote,
        quote_verifications[vote.opinion_id],
        relevance_verifications[vote.opinion_id],
        vote_verifications[vote.id]
      )
    end)
  end

  # Keep only quotes whose aggregate verification — authenticity → relevance →
  # vote answer — is positive (endorsed, verified or ai_verified). Disputed,
  # unverified and unverifiable quotes are excluded from the export.
  defp filter_verified(votes, statement_id) do
    opinion_ids = Enum.map(votes, & &1.opinion_id)
    relevance_status = relevance_status_by_opinion(statement_id, opinion_ids)

    Enum.filter(votes, fn vote ->
      VerificationStatus.aggregate(
        vote.opinion.verification_status,
        relevance_status[vote.opinion_id],
        vote.verification_status
      )
      |> VerificationStatus.positive?()
    end)
  end

  # Cached relevance status per opinion, from the opinion-statement join row
  # that links each quote to this statement.
  defp relevance_status_by_opinion(statement_id, opinion_ids) do
    from(os in OpinionStatement,
      where: os.statement_id == ^statement_id and os.opinion_id in ^opinion_ids,
      select: {os.opinion_id, os.verification_status}
    )
    |> Repo.all()
    |> Map.new()
  end

  # Latest relevance verification per opinion, resolved through the
  # opinion-statement join row that links each quote to this statement.
  defp relevance_verifications(statement_id, opinion_ids) do
    opinion_id_by_os_id =
      from(os in OpinionStatement,
        where: os.statement_id == ^statement_id and os.opinion_id in ^opinion_ids,
        select: {os.id, os.opinion_id}
      )
      |> Repo.all()
      |> Map.new()

    OpinionStatementVerifications.list_verifications(
      opinion_statement_id: Map.keys(opinion_id_by_os_id)
    )
    |> latest_by(&opinion_id_by_os_id[&1.opinion_statement_id])
  end

  # Latest vote verification per vote. A verification only applies while the
  # vote still points at the opinion it was stamped with.
  defp vote_verifications(votes) do
    opinion_id_by_vote_id = Map.new(votes, &{&1.id, &1.opinion_id})

    VoteVerifications.list_verifications(vote_id: Map.keys(opinion_id_by_vote_id))
    |> Enum.filter(&(&1.opinion_id == opinion_id_by_vote_id[&1.vote_id]))
    |> latest_by(& &1.vote_id)
  end

  defp latest_by(verifications, key_fun) do
    verifications
    |> Enum.group_by(key_fun)
    |> Map.new(fn {key, list} -> {key, Enum.max_by(list, & &1.id)} end)
  end

  defp row(statement, vote, quote_verification, relevance_verification, vote_verification) do
    opinion = vote.opinion
    author = opinion.author

    [
      statement.title,
      statement.id,
      url(~p"/p/#{statement.slug}"),
      opinion.id,
      url(~p"/c/#{opinion.id}"),
      author.name,
      SEO.author_url(author),
      author.bio,
      author.twitter_username && "https://x.com/#{author.twitter_username}",
      author.wikipedia_url,
      opinion.content,
      vote.answer,
      Opinion.date_iso(opinion),
      Opinion.date_precision_string(opinion),
      opinion.source_url
    ] ++
      verification_columns(quote_verification) ++
      verification_columns(relevance_verification) ++
      verification_columns(vote_verification)
  end

  defp verification_columns(nil), do: [nil, nil, nil]

  defp verification_columns(verification) do
    [
      verification.status,
      verification.comment,
      verification.inserted_at |> NaiveDateTime.to_date() |> Date.to_iso8601()
    ]
  end
end
