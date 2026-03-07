defmodule YouCongress.Statements.StatementQueriesTest do
  use YouCongress.DataCase, async: true

  import YouCongress.AuthorsFixtures
  import YouCongress.OpinionsFixtures
  import YouCongress.StatementsFixtures
  import YouCongress.VotesFixtures

  alias YouCongress.Statements.StatementQueries

  test "defaults to wikipedia authors when priority IDs are omitted" do
    wikipedia_author =
      author_fixture(%{
        name: "Ada Lovelace",
        wikipedia_url: "https://en.wikipedia.org/wiki/Ada_Lovelace"
      })

    non_wiki_author =
      author_fixture(%{
        name: "No Wiki Author",
        wikipedia_url: nil
      })

    statement = statement_fixture(%{title: "Default wikipedia prioritization"})

    non_wiki_opinion =
      opinion_fixture(%{
        statement_id: statement.id,
        author_id: non_wiki_author.id,
        content: "Non-wikipedia opinion"
      })

    vote_fixture(%{
      statement_id: statement.id,
      author_id: non_wiki_author.id,
      opinion_id: non_wiki_opinion.id
    })

    wiki_opinion =
      opinion_fixture(%{
        statement_id: statement.id,
        author_id: wikipedia_author.id,
        content: "Wikipedia opinion"
      })

    vote_fixture(%{
      statement_id: statement.id,
      author_id: wikipedia_author.id,
      opinion_id: wiki_opinion.id
    })

    [first_card] = StatementQueries.get_opinion_cards_round_robin(limit: 1)

    assert first_card.vote.author_id == wikipedia_author.id
  end

  test "keeps explicit top author priority when wikipedia IDs are omitted" do
    top_author =
      author_fixture(%{
        name: "Top Priority Author",
        wikipedia_url: nil
      })

    wikipedia_author =
      author_fixture(%{
        name: "Geoffrey Hinton",
        wikipedia_url: "https://en.wikipedia.org/wiki/Geoffrey_Hinton"
      })

    statement = statement_fixture(%{title: "Explicit top author prioritization"})

    wikipedia_opinion =
      opinion_fixture(%{
        statement_id: statement.id,
        author_id: wikipedia_author.id,
        content: "Wikipedia secondary opinion"
      })

    vote_fixture(%{
      statement_id: statement.id,
      author_id: wikipedia_author.id,
      opinion_id: wikipedia_opinion.id
    })

    top_opinion =
      opinion_fixture(%{
        statement_id: statement.id,
        author_id: top_author.id,
        content: "Top priority opinion"
      })

    vote_fixture(%{
      statement_id: statement.id,
      author_id: top_author.id,
      opinion_id: top_opinion.id
    })

    [first_card] =
      StatementQueries.get_opinion_cards_round_robin(
        top_author_ids: [top_author.id],
        limit: 1
      )

    assert first_card.vote.author_id == top_author.id
  end
end
