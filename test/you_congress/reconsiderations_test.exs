defmodule YouCongress.ReconsiderationsTest do
  use YouCongress.DataCase, async: true

  import YouCongress.AccountsFixtures
  import YouCongress.AuthorsFixtures
  import YouCongress.StatementsFixtures

  alias YouCongress.Accounts
  alias YouCongress.Authors
  alias YouCongress.Delegations
  alias YouCongress.Reconsiderations
  alias YouCongress.Votes

  setup do
    {:ok, creator} =
      user_fixture()
      |> Accounts.update_role("creator")

    username = "alice_#{System.unique_integer([:positive])}" |> String.slice(0, 15)

    {:ok, creator_author} =
      creator.author_id
      |> Authors.get_author!()
      |> Authors.update_author(%{username: username})

    creator = %{creator | author: creator_author}
    participant = user_fixture()
    delegate = author_fixture(%{name: "Featured guest"})
    first_statement = statement_fixture(%{title: "The first proposal should pass"})
    second_statement = statement_fixture(%{title: "The second proposal should pass"})

    {:ok, reconsideration} =
      Reconsiderations.create_reconsideration(
        creator,
        %{
          "title" => "A case worth reconsidering",
          "description" => "Watch and reflect.",
          "content_url" => "https://example.com/watch",
          "content_type" => "video"
        },
        [first_statement.id, second_statement.id],
        [delegate.id]
      )

    %{
      creator: creator,
      participant: participant,
      delegate: delegate,
      first_statement: first_statement,
      second_statement: second_statement,
      reconsideration: reconsideration
    }
  end

  test "records historical answers, current votes, and selected delegates", context do
    responses = %{
      to_string(context.first_statement.id) => %{"before" => "against", "after" => "for"},
      to_string(context.second_statement.id) => %{"before" => "for", "after" => "for"}
    }

    assert {:ok, saved} =
             Reconsiderations.submit_response(
               context.reconsideration,
               context.participant,
               responses,
               [context.delegate.id]
             )

    assert length(saved) == 2

    first_vote =
      Votes.get_by(
        author_id: context.participant.author_id,
        statement_id: context.first_statement.id
      )

    assert first_vote.answer == :for
    assert first_vote.direct

    historical =
      Reconsiderations.responses_for_author(
        context.reconsideration.id,
        context.participant.author_id
      )

    first_response = Enum.find(historical, &(&1.statement_id == context.first_statement.id))
    assert first_response.before_answer == :against
    assert first_response.after_answer == :for

    assert Delegations.delegating?(context.participant.author_id, context.delegate.id)

    stats = Reconsiderations.stats(context.reconsideration)
    assert stats.total_participants == 1
    assert stats.changed_participants == 1
    assert stats.changed_percent == 100

    assert stats.delegates == [
             %{
               author_id: context.delegate.id,
               author: context.delegate,
               count: 1,
               percent: 100
             }
           ]

    assert Enum.find(stats.statements, &(&1.statement_id == context.first_statement.id)).changed ==
             1

    assert Enum.find(stats.statements, &(&1.statement_id == context.second_statement.id)).changed ==
             0

    first_statement_stats =
      Enum.find(stats.statements, &(&1.statement_id == context.first_statement.id))

    assert first_statement_stats.transitions == [
             %{
               statement_id: context.first_statement.id,
               before_answer: :against,
               after_answer: :for,
               count: 1,
               percent: 100
             }
           ]
  end

  test "counts only delegations selected through this Reconsider page", context do
    participant_with_existing_delegation = user_fixture()

    assert {:ok, _} =
             Delegations.create_delegation(
               participant_with_existing_delegation,
               context.delegate.id
             )

    responses = %{
      to_string(context.first_statement.id) => %{"before" => "against", "after" => "for"},
      to_string(context.second_statement.id) => %{"before" => "for", "after" => "for"}
    }

    assert {:ok, _} =
             Reconsiderations.submit_response(
               context.reconsideration,
               context.participant,
               responses,
               [context.delegate.id]
             )

    assert {:ok, _} =
             Reconsiderations.submit_response(
               context.reconsideration,
               participant_with_existing_delegation,
               responses,
               []
             )

    assert [%{author_id: delegate_id, count: 1, percent: 50}] =
             Reconsiderations.stats(context.reconsideration).delegates

    assert delegate_id == context.delegate.id
  end

  test "groups every participant's before and after combination per statement", context do
    second_participant = user_fixture()

    assert {:ok, _} =
             Reconsiderations.submit_response(
               context.reconsideration,
               context.participant,
               %{
                 to_string(context.first_statement.id) => %{
                   "before" => "against",
                   "after" => "for"
                 },
                 to_string(context.second_statement.id) => %{
                   "before" => "for",
                   "after" => "for"
                 }
               },
               []
             )

    assert {:ok, _} =
             Reconsiderations.submit_response(
               context.reconsideration,
               second_participant,
               %{
                 to_string(context.first_statement.id) => %{
                   "before" => "for",
                   "after" => "for"
                 },
                 to_string(context.second_statement.id) => %{
                   "before" => "abstain",
                   "after" => "against"
                 }
               },
               []
             )

    first_statement_stats =
      context.reconsideration
      |> Reconsiderations.stats()
      |> Map.fetch!(:statements)
      |> Enum.find(&(&1.statement_id == context.first_statement.id))

    assert first_statement_stats.transitions == [
             %{
               statement_id: context.first_statement.id,
               before_answer: :for,
               after_answer: :for,
               count: 1,
               percent: 50
             },
             %{
               statement_id: context.first_statement.id,
               before_answer: :against,
               after_answer: :for,
               count: 1,
               percent: 50
             }
           ]
  end

  test "finds a page only under its creator username", context do
    found =
      Reconsiderations.get_reconsideration_by_username_and_slug!(
        String.upcase(context.creator.author.username),
        context.reconsideration.slug
      )

    assert found.id == context.reconsideration.id

    assert_raise Ecto.NoResultsError, fn ->
      Reconsiderations.get_reconsideration_by_username_and_slug!(
        "someone_else",
        context.reconsideration.slug
      )
    end
  end

  test "only accepts one completed response per author", context do
    responses = %{
      to_string(context.first_statement.id) => %{"before" => "for", "after" => "for"},
      to_string(context.second_statement.id) => %{"before" => "against", "after" => "against"}
    }

    assert {:ok, _} =
             Reconsiderations.submit_response(
               context.reconsideration,
               context.participant,
               responses,
               []
             )

    assert {:error, :already_submitted} =
             Reconsiderations.submit_response(
               context.reconsideration,
               context.participant,
               responses,
               []
             )
  end

  test "rejects incomplete answers and delegates not offered by the creator", context do
    incomplete = %{
      to_string(context.first_statement.id) => %{"before" => "for", "after" => "against"}
    }

    assert {:error, :incomplete_answers} =
             Reconsiderations.submit_response(
               context.reconsideration,
               context.participant,
               incomplete,
               []
             )

    complete = %{
      to_string(context.first_statement.id) => %{"before" => "for", "after" => "against"},
      to_string(context.second_statement.id) => %{"before" => "for", "after" => "for"}
    }

    unlisted_author = author_fixture()

    assert {:error, :invalid_delegates} =
             Reconsiderations.submit_response(
               context.reconsideration,
               context.participant,
               complete,
               [unlisted_author.id]
             )
  end

  test "creates a page from shareable statement and author references", context do
    attrs = %{
      "title" => "A referenced experience",
      "content_url" => "https://example.com/read",
      "content_type" => "article",
      "statement_refs" => "https://youcongress.org/p/#{context.first_statement.slug}",
      "delegate_refs" => "https://youcongress.org/a/#{context.delegate.id}"
    }

    assert {:ok, reconsideration} = Reconsiderations.create_from_refs(context.creator, attrs)

    assert Enum.map(reconsideration.reconsideration_statements, & &1.statement_id) == [
             context.first_statement.id
           ]

    assert Enum.map(reconsideration.delegates, & &1.author_id) == [context.delegate.id]
  end

  test "rejects experiences with more than three statements", context do
    third_statement = statement_fixture(%{title: "The third proposal should pass"})
    fourth_statement = statement_fixture(%{title: "The fourth proposal should pass"})

    assert {:error, "Choose between one and three statements."} =
             Reconsiderations.create_reconsideration(
               context.creator,
               %{
                 "title" => "Too many questions",
                 "content_url" => "https://example.com/too-many",
                 "content_type" => "article"
               },
               [
                 context.first_statement.id,
                 context.second_statement.id,
                 third_statement.id,
                 fourth_statement.id
               ],
               []
             )
  end

  test "pending authenticated actions save the complete Reconsider submission", context do
    pending =
      Jason.encode!(%{
        delegate_ids: [],
        votes: %{},
        reconsideration: %{
          slug: context.reconsideration.slug,
          responses: %{
            context.first_statement.id => %{before: "against", after: "for"},
            context.second_statement.id => %{before: "for", after: "for"}
          },
          delegate_ids: [context.delegate.id]
        }
      })

    assert :ok = YouCongress.PendingActions.process(context.participant, pending)

    assert Reconsiderations.participated?(
             context.reconsideration.id,
             context.participant.author_id
           )

    assert Delegations.delegating?(context.participant.author_id, context.delegate.id)
  end

  test "silently ignores a self-delegation selected before login", context do
    responses = %{
      to_string(context.first_statement.id) => %{"before" => "for", "after" => "for"},
      to_string(context.second_statement.id) => %{"before" => "against", "after" => "against"}
    }

    creator_as_participant = context.creator

    {:ok, reconsideration_with_creator} =
      Reconsiderations.create_reconsideration(
        context.creator,
        %{
          "title" => "An explicitly listed creator",
          "content_url" => "https://example.com/creator",
          "content_type" => "article"
        },
        [context.first_statement.id, context.second_statement.id],
        [context.creator.author_id]
      )

    assert {:ok, _} =
             Reconsiderations.submit_response(
               reconsideration_with_creator,
               creator_as_participant,
               responses,
               [creator_as_participant.author_id]
             )

    refute Delegations.delegating?(
             creator_as_participant.author_id,
             creator_as_participant.author_id
           )
  end
end
