defmodule YouCongress.Statements.QuotesCsv do
  @moduledoc """
  Builds the CSV export of a statement's sourced quotes.

  One row per quote-statement link — so an author with several quotes on the
  same statement gets one row per quote, not just the one their vote points
  at — with the latest verification of each kind: quote authenticity,
  statement relevance and vote answer. Only the most recent verification per
  kind is exported, not the full history.

  The header is the first row; the licence notice follows on the second and
  third rows, each prefixed with `# ` so it reads as a comment: YouCongress
  annotations are CC BY 4.0, while quote text and author bios are third-party
  content that remains its rights holders' property.
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
      "# License CC BY 4.0 (https://creativecommons.org/licenses/by/4.0/): the YouCongress annotations in this file — statement titles and statement-to-quote mapping, vote labels, verification statuses, comments and dates, and the column schema. Attribution: YouCongress (https://youcongress.org)."
    ],
    [
      "# Not licensed by us: quote text and author bios are third-party content reproduced as short excerpts under the right of quotation and remain the property of their respective rights holders. See each row's source_url for the original source."
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
    "source_text",
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

  defp dump([headers | rows]) do
    ([headers] ++ @license_rows ++ rows)
    |> CSV.dump_to_iodata()
    |> IO.iodata_to_binary()
  end

  defp rows(%Statement{} = statement) do
    votes_by_author = votes_by_author(statement.id)
    vote_verifications = vote_verifications(votes_by_author)

    links =
      statement.id
      |> quote_links()
      |> filter_verified(votes_by_author, vote_verifications)

    quote_verifications =
      Verifications.list_verifications(opinion_id: Enum.map(links, & &1.opinion_id))
      |> latest_by(& &1.opinion_id)

    relevance_verifications =
      OpinionStatementVerifications.list_verifications(
        opinion_statement_id: Enum.map(links, & &1.id)
      )
      |> latest_by(& &1.opinion_statement_id)

    Enum.map(links, fn link ->
      vote = votes_by_author[link.opinion.author_id]

      row(
        statement,
        link.opinion,
        vote,
        quote_verifications[link.opinion_id],
        relevance_verifications[link.id],
        latest_vote_verification(vote_verifications, vote, link)
      )
    end)
  end

  # Every sourced quote linked to the statement — one link per quote, so
  # authors with several quotes on the statement contribute several rows.
  defp quote_links(statement_id) do
    from(os in OpinionStatement,
      join: o in assoc(os, :opinion),
      join: a in assoc(o, :author),
      where: os.statement_id == ^statement_id,
      where: not (is_nil(o.source_url) and is_nil(o.source_text)),
      order_by: [desc_nulls_last: o.date, desc: o.id],
      preload: [opinion: {o, author: a}]
    )
    |> Repo.all()
  end

  defp votes_by_author(statement_id) do
    statement_id
    |> Votes.list_votes()
    |> Map.new(&{&1.author_id, &1})
  end

  # Keep only quotes whose aggregate verification — authenticity → relevance →
  # vote answer — is positive (endorsed, verified or ai_verified). Disputed,
  # unverified and unverifiable quotes are excluded from the export.
  defp filter_verified(links, votes_by_author, vote_verifications) do
    Enum.filter(links, fn link ->
      vote = votes_by_author[link.opinion.author_id]

      VerificationStatus.aggregate(
        link.opinion.verification_status,
        link.verification_status,
        vote_status(vote_verifications, vote, link)
      )
      |> VerificationStatus.positive?()
    end)
  end

  # Vote verifications grouped by the quote they were stamped with, so each
  # quote row resolves the vote answer against its own verification trail.
  defp vote_verifications(votes_by_author) do
    vote_ids = votes_by_author |> Map.values() |> Enum.map(& &1.id)

    VoteVerifications.list_verifications(vote_id: vote_ids)
    |> Enum.group_by(&{&1.vote_id, &1.opinion_id})
  end

  defp vote_status(_vote_verifications, nil, _link), do: nil

  defp vote_status(vote_verifications, vote, link) do
    vote_verifications
    |> Map.get({vote.id, link.opinion_id}, [])
    |> VerificationStatus.resolve_from_list()
  end

  defp latest_vote_verification(_vote_verifications, nil, _link), do: nil

  defp latest_vote_verification(vote_verifications, vote, link) do
    vote_verifications
    |> Map.get({vote.id, link.opinion_id}, [])
    |> Enum.max_by(& &1.id, fn -> nil end)
  end

  defp latest_by(verifications, key_fun) do
    verifications
    |> Enum.group_by(key_fun)
    |> Map.new(fn {key, list} -> {key, Enum.max_by(list, & &1.id)} end)
  end

  defp row(statement, opinion, vote, quote_verification, relevance_verification, vote_verification) do
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
      opinion.source_url,
      opinion.source_text
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
