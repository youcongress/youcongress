defmodule YouCongress.TrustNetworkTest do
  use YouCongress.DataCase
  import YouCongress.AccountsFixtures
  import YouCongress.AuthorsFixtures
  import YouCongress.CountriesFixtures
  import YouCongress.HallsFixtures
  import Swoosh.TestAssertions
  alias YouCongress.{Councils, TrustNetwork, TrustRankings}

  test "nominee country does not change the audience denominator and memberships are independent" do
    country = country_fixture(%{name: "Trustland", iso_alpha2: "TT", iso_alpha3: "TTT"})
    alice = user_fixture()
    bob = user_fixture()
    one = author_fixture(%{country_id: country.id})
    two = author_fixture()
    {:ok, _} = Councils.add_member(alice, one.id)
    {:ok, _} = Councils.add_member(bob, two.id)
    result = TrustRankings.ranking("general", %{"nominees" => to_string(country.id)})
    assert result.participants == 2
    assert [%{count: 1, share: 50.0}] = result.rows
    hall = hall_fixture()

    {:ok, _} =
      TrustNetwork.configure_community(admin_fixture(), hall.id, %{community_enabled: true})

    {:ok, _} = TrustNetwork.join(alice, hall.id)
    assert TrustRankings.ranking("general", %{"community" => hall.id}).participants == 1
    assert TrustRankings.ranking("general").participants == 2
    TrustNetwork.leave(alice, hall.id)
    assert TrustRankings.ranking("general", %{"community" => hall.id}).participants == 0
    assert TrustRankings.ranking("general").participants == 2
  end

  test "blocked participants are excluded and repeated Council lists are rejected" do
    user = user_fixture()
    nominee = author_fixture()
    {:ok, council} = Councils.add_member(user, nominee.id)
    attrs = Councils.editable(council)
    extra = %{name: "Inner circle", hall_id: nil, members: [%{author_id: nominee.id}]}
    {:error, :invalid_order} = Councils.save(user, %{attrs | lists: [extra | attrs.lists]})
    assert [%{count: 1, share: 100.0}] = TrustRankings.ranking("general").rows
    {:ok, blocked} = YouCongress.Accounts.update_role(user, "blocked")
    assert TrustRankings.ranking("general").participants == 0

    assert {:error, :forbidden} =
             Councils.save(blocked, Councils.editable(Councils.get(user.author_id)))
  end

  test "requests and notifications are private; only reviewers can resolve" do
    alice = user_fixture()
    bob = user_fixture()

    {:ok, request} =
      TrustNetwork.request(alice, %{kind: "missing_position", body: "Where is the evidence?"})

    assert TrustNetwork.requests(bob) == []
    assert {:error, :forbidden} = TrustNetwork.resolve(bob, request.id, "resolved", "Pretending")
    {:ok, _} = TrustNetwork.notify(alice.author_id, "private", "Private update", "/council")
    notice = hd(TrustNetwork.notifications(alice))
    assert TrustNetwork.notifications(bob) == []
    assert {0, _} = TrustNetwork.read(bob, notice.id)
    assert TrustNetwork.unread_count(alice) == 1
  end

  test "digest is off by default, opt-in delivers once, and opt-out is checked at delivery" do
    user = user_fixture()
    {:ok, _} = Councils.ensure(user.author_id)
    {:ok, _} = TrustNetwork.notify(user.author_id, "digest", "Updated council", "/council")
    job = %Oban.Job{args: %{"author_id" => user.author_id}}
    assert :ok = YouCongress.Workers.TrustDigestWorker.perform(job)
    refute_email_sent(subject: "Your YouCongress updates")
    {:ok, _} = Councils.settings(user, %{digest: "daily"})
    assert :ok = YouCongress.Workers.TrustDigestWorker.perform(job)
    assert_email_sent(subject: "Your YouCongress updates")
    assert :ok = YouCongress.Workers.TrustDigestWorker.perform(job)
    refute_email_sent(subject: "Your YouCongress updates")
    {:ok, _} = TrustNetwork.notify(user.author_id, "digest-2", "Another update", "/council")
    {:ok, _} = Councils.settings(user, %{digest: "off"})
    assert :ok = YouCongress.Workers.TrustDigestWorker.perform(job)
    refute_email_sent(subject: "Your YouCongress updates")
  end

  test "independent recommendations add to the one Council" do
    user = user_fixture()
    nominee = author_fixture()

    {:ok, rec} =
      TrustNetwork.recommend(user, %{
        nominee_id: nominee.id,
        scope: "ai-safety",
        reason: "Careful evidence",
        published: true
      })

    assert TrustRankings.ranking("ai-safety").rows == []
    {:ok, _} = TrustNetwork.add_recommendation_to_council(user, rec)
    assert [%{author_id: id}] = TrustRankings.ranking("general").rows
    assert id == nominee.id
    assert List.last(Councils.get(user.author_id).lists).fallback
    TrustNetwork.delete_recommendation(user, rec.id)
    assert TrustRankings.ranking("general").participants == 1
  end

  test "unsafe recommendation URLs and malformed guest drafts are rejected" do
    user = user_fixture()
    nominee = author_fixture()

    assert {:error, _} =
             TrustNetwork.recommend(user, %{
               nominee_id: nominee.id,
               scope: "general",
               source_url: "javascript:alert(1)"
             })

    assert {:error, _} =
             YouCongress.Councils.Draft.normalize(%{"lists" => [%{"members" => "bad"}]})
  end

  test "author merge preserves repeated lists and deduplicates nominations" do
    user = user_fixture()
    first = author_fixture()
    second = author_fixture()
    {:ok, _} = Councils.add_member(user, first.id)
    {:ok, _} = Councils.add_member(user, second.id)
    {:ok, result} = YouCongress.Authors.merge_authors(first.id, second.id)
    assert [%{author_id: id, count: 1}] = TrustRankings.ranking("general").rows
    assert id == result.survivor_id
  end

  test "community results count participant ballots and council decisions separately" do
    admin = admin_fixture()
    user = user_fixture()
    expert = author_fixture()
    hall = hall_fixture()

    {:ok, _} =
      TrustNetwork.configure_community(admin, hall.id, %{
        community_enabled: true,
        organizer_id: user.id
      })

    {:ok, _} = TrustNetwork.join(user, hall.id)

    {:ok, statement} =
      TrustNetwork.create_community_statement(user, hall.id, "A community proposal")

    assert {:error, :forbidden} =
             TrustNetwork.create_community_statement(user_fixture(), hall.id, "Unauthorized")

    YouCongress.VotesFixtures.vote_fixture(%{
      author_id: expert.id,
      statement_id: statement.id,
      answer: :for
    })

    # A sourced profile record can coexist with the user's council decision.
    YouCongress.Repo.insert!(%YouCongress.Votes.Vote{
      author_id: user.author_id,
      statement_id: statement.id,
      origin: "inferred",
      answer: :against
    })

    {:ok, _} = Councils.add_member(user, expert.id)
    assert [%{direct: false, answer: "for", count: 1}] = TrustNetwork.community_results(hall.id)

    {:ok, _} =
      YouCongress.Votes.create_or_update(%{
        user_id: user.id,
        author_id: user.author_id,
        statement_id: statement.id,
        direct: true,
        answer: :abstain
      })

    assert [%{direct: true, answer: "abstain", count: 1}] =
             TrustNetwork.community_results(hall.id)

    TrustNetwork.leave(user, hall.id)
    assert [] = TrustNetwork.community_results(hall.id)
  end

  test "changed source evidence cannot inherit old verification approvals" do
    admin = admin_fixture()
    opinion = YouCongress.OpinionsFixtures.opinion_fixture(%{twin: false})

    {:ok, _} =
      YouCongress.Verifications.create_verification(admin, %{
        opinion_id: opinion.id,
        status: :verified
      })

    {:ok, changed} =
      YouCongress.Opinions.update_opinion(opinion, %{
        source_url: "https://example.org/corrected-evidence"
      })

    assert changed.evidence_revision == 2
    YouCongress.Verifications.update_opinion_verification_status(opinion.id)
    assert YouCongress.Opinions.get_opinion!(opinion.id).verification_status == nil

    {:ok, verification} =
      YouCongress.Verifications.create_verification(admin, %{
        opinion_id: opinion.id,
        status: :verified
      })

    assert verification.evidence_revision == 2
    assert YouCongress.Opinions.get_opinion!(opinion.id).verification_status == :verified
  end
end
