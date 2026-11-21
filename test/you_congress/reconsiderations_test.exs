defmodule YouCongress.ReconsiderationsTest do
  use YouCongress.DataCase, async: true
  use Oban.Testing, repo: YouCongress.Repo

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

  test "removing a response also removes its current votes and selected delegates", context do
    responses = %{
      to_string(context.first_statement.id) => %{"before" => "against", "after" => "for"},
      to_string(context.second_statement.id) => %{"before" => "for", "after" => "against"}
    }

    assert {:ok, _} =
             Reconsiderations.submit_response(
               context.reconsideration,
               context.participant,
               responses,
               [context.delegate.id]
             )

    assert {:ok, :removed} =
             Reconsiderations.remove_response(context.reconsideration, context.participant)

    refute Reconsiderations.participated?(
             context.reconsideration.id,
             context.participant.author_id
           )

    assert Reconsiderations.responses_for_author(
             context.reconsideration.id,
             context.participant.author_id
           ) == []

    assert Votes.get_by(
             author_id: context.participant.author_id,
             statement_id: context.first_statement.id
           ) == nil

    assert Votes.get_by(
             author_id: context.participant.author_id,
             statement_id: context.second_statement.id
           ) == nil

    refute Delegations.delegating?(context.participant.author_id, context.delegate.id)
    assert Reconsiderations.stats(context.reconsideration).total_participants == 0
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

  test "rejects incomplete answers and accepts any existing author as a delegate", context do
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

    assert {:ok, _responses} =
             Reconsiderations.submit_response(
               context.reconsideration,
               context.participant,
               complete,
               [unlisted_author.id]
             )

    assert Delegations.delegating?(context.participant.author_id, unlisted_author.id)

    assert Enum.any?(
             Reconsiderations.stats(context.reconsideration).delegates,
             &(&1.author_id == unlisted_author.id and &1.count == 1)
           )
  end

  test "rejects delegate IDs that do not identify an author", context do
    responses = %{
      to_string(context.first_statement.id) => %{"before" => "for", "after" => "against"},
      to_string(context.second_statement.id) => %{"before" => "for", "after" => "for"}
    }

    assert {:error, :invalid_delegates} =
             Reconsiderations.submit_response(
               context.reconsideration,
               context.participant,
               responses,
               [-1]
             )
  end

  test "creates new delegate profiles from X, Wikipedia, or name and bio", context do
    responses = %{
      to_string(context.first_statement.id) => %{"before" => "for", "after" => "against"},
      to_string(context.second_statement.id) => %{"before" => "for", "after" => "for"}
    }

    x_username = "trust_#{System.unique_integer([:positive])}" |> String.slice(0, 15)
    wiki_name = "Trust_Person_#{System.unique_integer([:positive])}"
    named_person = "Community expert #{System.unique_integer([:positive])}"

    new_people = [
      %{"x" => "https://x.com/#{x_username}"},
      %{"wikipedia_url" => "https://en.wikipedia.org/wiki/#{wiki_name}"},
      %{"name" => named_person, "bio" => "A trusted local subject-matter expert."}
    ]

    assert {:ok, _responses} =
             Reconsiderations.submit_response(
               context.reconsideration,
               context.participant,
               responses,
               [],
               nil,
               new_people
             )

    x_author = Authors.get_author_by(twitter_username: x_username)

    wiki_author =
      Authors.get_author_by(wikipedia_url: "https://en.wikipedia.org/wiki/#{wiki_name}")

    named_author = Authors.get_author_by(name: named_person)

    assert x_author.twin_origin == false
    assert wiki_author.name == String.replace(wiki_name, "_", " ")
    assert named_author.bio == "A trusted local subject-matter expert."

    stats = Reconsiderations.stats(context.reconsideration)

    assert Enum.all?([x_author.id, wiki_author.id, named_author.id], fn author_id ->
             Enum.any?(stats.delegates, &(&1.author_id == author_id and &1.count == 1))
           end)
  end

  test "reuses identity matches and rejects conflicting X and Wikipedia identities", context do
    responses = %{
      to_string(context.first_statement.id) => %{"before" => "for", "after" => "against"},
      to_string(context.second_statement.id) => %{"before" => "for", "after" => "for"}
    }

    x_author = author_fixture(twitter_username: "existing_trust")

    assert {:ok, _responses} =
             Reconsiderations.submit_response(
               context.reconsideration,
               context.participant,
               responses,
               [],
               nil,
               [%{"x" => "@EXISTING_TRUST"}]
             )

    assert Delegations.delegating?(context.participant.author_id, x_author.id)

    other_participant = user_fixture()

    wikipedia_author =
      author_fixture(wikipedia_url: "https://en.wikipedia.org/wiki/Other_Trust_Person")

    assert {:error, {:invalid_person, message}} =
             Reconsiderations.submit_response(
               context.reconsideration,
               other_participant,
               responses,
               [],
               nil,
               [
                 %{
                   "x" => "existing_trust",
                   "wikipedia_url" => wikipedia_author.wikipedia_url
                 }
               ]
             )

    assert message =~ "different people"
    refute Reconsiderations.participated?(context.reconsideration.id, other_participant.author_id)
  end

  test "validates new-person routes and rolls profile creation back with the response", context do
    responses = %{
      to_string(context.first_statement.id) => %{"before" => "for", "after" => "against"},
      to_string(context.second_statement.id) => %{"before" => "for", "after" => "for"}
    }

    assert {:error, {:invalid_person, _message}} =
             Reconsiderations.submit_response(
               context.reconsideration,
               context.participant,
               responses,
               [],
               nil,
               [%{"name" => "Missing bio"}]
             )

    rolled_back_name = "Rolled back #{System.unique_integer([:positive])}"

    assert {:error, :invalid_list} =
             Reconsiderations.submit_response(
               context.reconsideration,
               context.participant,
               responses,
               [],
               999_999_999,
               [%{"name" => rolled_back_name, "bio" => "Should not remain in the database."}]
             )

    assert Authors.get_author_by(name: rolled_back_name) == nil
  end

  test "blocked users cannot create people through a Reconsider response", context do
    {:ok, blocked_participant} = Accounts.update_role(context.participant, "blocked")

    responses = %{
      to_string(context.first_statement.id) => %{"before" => "for", "after" => "against"},
      to_string(context.second_statement.id) => %{"before" => "for", "after" => "for"}
    }

    assert {:error, :forbidden} =
             Reconsiderations.submit_response(
               context.reconsideration,
               blocked_participant,
               responses,
               [],
               nil,
               [%{"name" => "Blocked creation", "bio" => "Must not be created."}]
             )

    assert Authors.get_author_by(name: "Blocked creation") == nil
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

  test "queues a notification with the creator name and page URL", context do
    Oban.Testing.with_testing_mode(:manual, fn ->
      assert {:ok, reconsideration} =
               Reconsiderations.create_reconsideration(
                 context.creator,
                 %{
                   "title" => "A newly created page",
                   "content_url" => "https://example.com/newly-created",
                   "content_type" => "article"
                 },
                 [context.first_statement.id],
                 []
               )

      assert_enqueued(
        worker: YouCongress.Workers.ReconsiderationCreatedNotificationWorker,
        args: %{
          "creator_name" => context.creator.author.name,
          "reconsideration_url" =>
            YouCongressWeb.Endpoint.url() <>
              "/@#{context.creator.author.username}/r/#{reconsideration.slug}"
        }
      )
    end)
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

  test "pending authenticated actions create a staged person", context do
    new_name = "Pending expert #{System.unique_integer([:positive])}"

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
          delegate_ids: [],
          new_people: [%{name: new_name, bio: "Added before authentication."}]
        }
      })

    assert :ok = YouCongress.PendingActions.process(context.participant, pending)

    author = Authors.get_author_by(name: new_name)
    assert author
    assert Delegations.delegating?(context.participant.author_id, author.id)
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

  test "removing a response preserves a later independent vote and pre-existing council selection",
       context do
    user = context.participant
    {:ok, _} = YouCongress.Councils.add_member(user, context.delegate.id)

    responses = %{
      to_string(context.first_statement.id) => %{"before" => "against", "after" => "for"},
      to_string(context.second_statement.id) => %{"before" => "against", "after" => "for"}
    }

    {:ok, _} =
      Reconsiderations.submit_response(context.reconsideration, user, responses, [
        context.delegate.id
      ])

    {:ok, _} =
      Votes.create_or_update(%{
        user_id: user.id,
        author_id: user.author_id,
        statement_id: context.first_statement.id,
        direct: true,
        answer: :abstain
      })

    {:ok, _} = Reconsiderations.remove_response(context.reconsideration, user)

    assert Votes.get_by(author_id: user.author_id, statement_id: context.first_statement.id).answer ==
             :abstain

    assert context.delegate.id in YouCongress.Councils.delegate_ids(user.author_id)
  end

  test "removing a response restores the previous inferred position's provenance", context do
    user = context.participant

    prior =
      YouCongress.Repo.insert!(%Votes.Vote{
        author_id: user.author_id,
        statement_id: context.first_statement.id,
        answer: :against,
        origin: "inferred"
      })

    responses = %{
      to_string(context.first_statement.id) => %{"before" => "against", "after" => "for"},
      to_string(context.second_statement.id) => %{"before" => "against", "after" => "for"}
    }

    {:ok, _} = Reconsiderations.submit_response(context.reconsideration, user, responses, [])
    {:ok, _} = Reconsiderations.remove_response(context.reconsideration, user)
    restored = Votes.get_by(author_id: user.author_id, statement_id: context.first_statement.id)
    assert restored.id == prior.id
    assert restored.answer == :against
    assert restored.origin == "inferred"
    assert is_nil(restored.cast_by_user_id)
  end
end
