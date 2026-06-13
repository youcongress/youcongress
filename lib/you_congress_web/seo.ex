defmodule YouCongressWeb.SEO do
  @moduledoc """
  Builds page titles, meta descriptions and schema.org JSON-LD data for
  public pages, so they rank for question-format queries ("what does X
  think about Y?") and are easy for AI assistants to cite.
  """

  use YouCongressWeb, :verified_routes

  alias YouCongress.Opinions.Opinion
  alias YouCongress.Tools.StringUtils

  @doc """
  Question-format title for an author page.

  `halls` is the list of `{hall_name, count}` tuples already computed by
  the author page, sorted by frequency.
  """
  def author_title(name, halls) do
    "What does #{name} say about #{author_topic(halls)}? | YouCongress"
  end

  def author_description(name, halls) do
    case top_hall_topics(halls, 3) do
      [] ->
        "Verified quotes and votes from #{name} on AI policy statements. " <>
          "See where they stand — for or against — with sources."

      topics ->
        "Verified quotes and votes from #{name} on #{join_topics(topics)}. " <>
          "See where they stand — for or against — on AI policy statements."
    end
  end

  def statement_description(title, vote_frequencies, quotes_votes_count)
      when is_integer(quotes_votes_count) and quotes_votes_count > 0 do
    {_, for_pct} = vote_frequencies[:for] || {0, 0}
    {_, against_pct} = vote_frequencies[:against] || {0, 0}

    "Who's for and against \"#{truncate(title, 70)}\"? " <>
      "#{quotes_votes_count} verified expert #{plural(quotes_votes_count, "quote")} — " <>
      "#{for_pct}% for, #{against_pct}% against. Sources included."
  end

  def statement_description(title, _vote_frequencies, _quotes_votes_count) do
    "Who's for and against \"#{truncate(title, 90)}\"? " <>
      "See expert quotes, votes and sources on YouCongress."
  end

  def hall_title(hall_name) do
    "Expert opinions on #{StringUtils.titleize_hall(hall_name)} | YouCongress"
  end

  def hall_description(hall_name, stats \\ nil)

  def hall_description(hall_name, %{quote_count: quotes, statement_count: statements})
      when quotes > 0 do
    topic = StringUtils.titleize_hall(hall_name)

    "What do experts say about #{topic}? #{quotes} verified #{plural(quotes, "quote")} " <>
      "for and against, with votes and sources, across #{statements} " <>
      "#{plural(statements, "statement")}."
  end

  def hall_description(hall_name, _stats) do
    topic = StringUtils.titleize_hall(hall_name)

    "What do experts say about #{topic}? Verified quotes for and against, " <>
      "with votes and sources, from AI researchers and policymakers."
  end

  @doc """
  Title for a quote page: the author plus the topic (first linked
  statement, falling back to a generic AI topic).
  """
  def opinion_title(opinion) do
    name = opinion.author.name || opinion.author.twitter_username || "Anonymous"
    "#{name} on #{opinion_topic(opinion)} | YouCongress"
  end

  def opinion_description(opinion) do
    name = opinion.author.name || opinion.author.twitter_username || "Anonymous"
    date = if Opinion.display_date(opinion), do: ", #{Opinion.display_date(opinion)}"
    "\"#{truncate(opinion.content, 110)}\" — #{name}#{date}. Verified quote with source."
  end

  # --- JSON-LD builders (schema.org) ---

  def person(author, canonical_url) do
    same_as =
      Enum.reject(
        [
          author.twitter_username && "https://x.com/#{author.twitter_username}",
          author.wikipedia_url
        ],
        &is_nil/1
      )

    %{
      "@context" => "https://schema.org",
      "@type" => "Person",
      "name" => author.name || author.twitter_username,
      "url" => canonical_url
    }
    |> put_if("description", author.bio || author.description)
    |> put_if("image", author.profile_image_url)
    |> put_if("sameAs", if(same_as != [], do: same_as))
  end

  @doc """
  A single schema.org Quotation for a sourced, human (non-twin) opinion.
  """
  def quotation(opinion, opts \\ []) do
    author = opinion.author

    creator =
      %{
        "@type" => "Person",
        "name" => author.name || author.twitter_username,
        "url" => author_url(author)
      }

    %{
      "@type" => "Quotation",
      "text" => opinion.content,
      "url" => url(~p"/c/#{opinion.id}"),
      "creator" => creator
    }
    |> put_if("citation", opinion.source_url)
    |> put_if("dateCreated", schema_date(opinion))
    |> put_if("isPartOf", opts[:is_part_of])
    |> put_if("@context", if(opts[:root], do: "https://schema.org"))
  end

  @doc """
  WebPage + ItemList of Quotation for a statement page. Only sourced,
  non-twin opinions are included — AI-generated content must never be
  presented as a real quote.
  """
  def statement_graph(statement, votes, canonical_url) do
    quotations =
      votes
      |> Enum.filter(&citable_vote?/1)
      |> Enum.with_index(1)
      |> Enum.map(fn {vote, position} ->
        vote.opinion
        |> quotation()
        |> Map.put("position", position)
      end)

    web_page =
      %{
        "@type" => "WebPage",
        "@id" => canonical_url,
        "name" => statement.title,
        "url" => canonical_url
      }
      |> put_if("dateModified", iso8601(statement.updated_at))

    item_list = %{
      "@type" => "ItemList",
      "name" => "Verified quotes on: #{statement.title}",
      "itemListElement" => quotations,
      "numberOfItems" => length(quotations)
    }

    %{
      "@context" => "https://schema.org",
      "@graph" => [web_page, item_list]
    }
  end

  def collection_page(hall_name, description, statement_urls) do
    %{
      "@context" => "https://schema.org",
      "@type" => "CollectionPage",
      "name" => "Expert opinions on #{StringUtils.titleize_hall(hall_name)}",
      "url" => url(~p"/h/#{hall_name}"),
      "description" => description,
      "hasPart" => %{
        "@type" => "ItemList",
        "itemListElement" =>
          statement_urls
          |> Enum.with_index(1)
          |> Enum.map(fn {statement_url, position} ->
            %{"@type" => "ListItem", "position" => position, "url" => statement_url}
          end)
      }
    }
  end

  def website do
    %{
      "@context" => "https://schema.org",
      "@type" => "WebSite",
      "name" => "YouCongress",
      "url" => url(~p"/"),
      "potentialAction" => %{
        "@type" => "SearchAction",
        "target" => %{
          "@type" => "EntryPoint",
          "urlTemplate" => url(~p"/") <> "?search={search_term_string}"
        },
        "query-input" => "required name=search_term_string"
      }
    }
  end

  @doc """
  Canonical path for an author, preferring the /x/ username URL —
  /a/:id pages canonicalize to it so the two routes don't compete.
  """
  def author_path(%{twitter_username: nil, id: author_id}), do: ~p"/a/#{author_id}"
  def author_path(%{twitter_username: username}), do: ~p"/x/#{username}"

  def author_url(%{twitter_username: nil, id: author_id}), do: url(~p"/a/#{author_id}")
  def author_url(%{twitter_username: username}), do: url(~p"/x/#{username}")

  def citable_vote?(vote) do
    vote.opinion && vote.opinion.source_url && !vote.twin && !vote.opinion.twin
  end

  def truncate(text, max_length) when is_binary(text) do
    if String.length(text) <= max_length do
      text
    else
      String.slice(text, 0, max_length - 1) <> "…"
    end
  end

  defp author_topic(halls) do
    case top_hall_topics(halls, 1) do
      [topic] -> topic
      [] -> "AI"
    end
  end

  defp top_hall_topics(halls, count) do
    halls
    |> Enum.map(fn {hall_name, _count} -> hall_name end)
    |> Enum.reject(&(&1 in ["all", "ai"]))
    |> Enum.take(count)
    |> Enum.map(&StringUtils.titleize_hall/1)
  end

  defp join_topics([topic]), do: topic

  defp join_topics(topics) do
    {rest, [last]} = Enum.split(topics, -1)
    Enum.join(rest, ", ") <> " and " <> last
  end

  defp opinion_topic(opinion) do
    case opinion.statements do
      [statement | _] -> truncate(statement.title, 40)
      _ -> "AI"
    end
  end

  defp put_if(map, _key, nil), do: map
  defp put_if(map, key, value), do: Map.put(map, key, value)

  defp schema_date(%{date: nil}), do: nil
  defp schema_date(%{date_precision: :year} = opinion), do: Opinion.display_date(opinion)
  defp schema_date(%{date_precision: :month} = opinion), do: Opinion.display_date(opinion)
  defp schema_date(opinion), do: Opinion.date_iso(opinion)

  defp plural(1, word), do: word
  defp plural(_, word), do: word <> "s"

  defp iso8601(nil), do: nil

  defp iso8601(%NaiveDateTime{} = naive) do
    naive
    |> DateTime.from_naive!("Etc/UTC")
    |> DateTime.truncate(:second)
    |> DateTime.to_iso8601()
  end

  defp iso8601(%DateTime{} = dt), do: dt |> DateTime.truncate(:second) |> DateTime.to_iso8601()
end
