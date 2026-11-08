defmodule YouCongress.TopicCouncilsTest do
  use YouCongress.DataCase
  use Oban.Testing, repo: YouCongress.Repo
  import YouCongress.AccountsFixtures
  import YouCongress.AuthorsFixtures
  import YouCongress.StatementsFixtures
  import YouCongress.VotesFixtures
  alias YouCongress.{Councils, HallsStatements, PeopleLists, Repo}
  alias YouCongress.Councils.{Draft, Evaluator}

  test "only matching halls are consulted; repeated General lists apply everywhere" do
    user = user_fixture()
    statement = statement_fixture()
    yes = author_fixture()
    no = author_fixture()
    vote_fixture(%{author_id: yes.id, statement_id: statement.id, answer: :for})
    vote_fixture(%{author_id: no.id, statement_id: statement.id, answer: :against})
    {:ok, council} = Councils.ensure(user.author_id)
    [gov, jobs, environment, general] = Councils.editable(council).lists

    assert {:ok, _} =
             HallsStatements.sync!(statement.id, %{main_tag: "environment", other_tags: []})

    lists = [
      %{gov | members: [%{author_id: yes.id}]},
      %{jobs | members: [%{author_id: yes.id}]},
      %{environment | members: [%{author_id: no.id}]},
      %{general | members: [%{author_id: yes.id}]}
    ]

    {:ok, council} = Councils.save(user, %{version: council.version, lists: lists})
    explanation = Councils.explain(user.author_id, statement.id)
    assert explanation.answer == :against
    assert explanation.deciding_list_id == environment.id

    assert Enum.map(explanation.lists, & &1.status) == [
             :not_matching,
             :not_matching,
             :deciding,
             :not_needed
           ]

    extra = %{name: "My most trusted people", hall_id: nil, members: [%{author_id: yes.id}]}

    {:ok, council} =
      Councils.save(user, %{
        Councils.editable(council)
        | lists: [extra | Councils.editable(council).lists]
      })

    assert hd(council.lists).fallback == false
    assert List.last(council.lists).fallback
    assert Councils.explain(user.author_id, statement.id).answer == :for

    assert {:ok, _} =
             HallsStatements.sync!(statement.id, %{main_tag: "other-topic", other_tags: []})

    assert Councils.explain(user.author_id, statement.id).answer == :for
  end

  test "a repeated matching hall can decide after the first is tied" do
    lists = [
      %{
        id: 1,
        name: "Policy",
        hall_id: 10,
        fallback: false,
        members: [%{author_id: 1}, %{author_id: 2}, %{author_id: 3}]
      },
      %{
        id: 2,
        name: "Policy inner circle",
        hall_id: 10,
        fallback: false,
        members: [%{author_id: 2}]
      },
      %{id: 3, name: "General", hall_id: nil, fallback: true, members: [%{author_id: 1}]}
    ]

    positions = %{
      1 => %{author_id: 1, answer: :for},
      2 => %{author_id: 2, answer: :against},
      3 => %{author_id: 3, answer: :abstain}
    }

    assert %{
             answer: :against,
             deciding_list_id: 2,
             lists: [
               %{threshold: 2, status: :no_majority},
               %{status: :deciding},
               %{status: :not_needed}
             ]
           } = Evaluator.evaluate(lists, positions, [10])

    assert %{answer: :for, deciding_list_id: 3} = Evaluator.evaluate(lists, positions, [20])
    assert %{answer: nil} = Evaluator.evaluate(lists, %{}, [10])
  end

  test "only For and Against determine the majority, regardless of abstentions and missing positions" do
    list = %{
      id: 1,
      name: "General",
      hall_id: nil,
      fallback: true,
      members: Enum.map(1..58, &%{author_id: &1})
    }

    for {for_count, against_count, expected} <- [
          {8, 0, :for},
          {0, 8, :against},
          {8, 7, :for},
          {7, 8, :against},
          {8, 8, nil},
          {0, 0, nil}
        ] do
      positions =
        list.members
        |> Enum.with_index()
        |> Map.new(fn {member, index} ->
          answer =
            cond do
              index < for_count -> :for
              index < for_count + against_count -> :against
              index == for_count + against_count -> :abstain
              true -> nil
            end

          {member.author_id, Map.put(member, :answer, answer)}
        end)

      assert Evaluator.evaluate([list], positions).answer == expected
    end
  end

  test "hall retagging queues recalculation and direct votes still override" do
    user = user_fixture()
    person = author_fixture()
    statement = statement_fixture()
    vote_fixture(%{author_id: person.id, statement_id: statement.id, answer: :for})
    {:ok, council} = Councils.ensure(user.author_id)
    {:ok, _} = Councils.add_member(user, person.id, hd(council.lists).id)
    assert Councils.explain(user.author_id, statement.id).answer == nil
    {:ok, _} = HallsStatements.sync!(statement.id, %{main_tag: "ai-governance", other_tags: []})
    assert Councils.explain(user.author_id, statement.id).answer == :for

    assert YouCongress.Votes.get_by(author_id: user.author_id, statement_id: statement.id).answer ==
             :for

    {:ok, _} =
      YouCongress.Votes.create_or_update(%{
        author_id: user.author_id,
        user_id: user.id,
        statement_id: statement.id,
        answer: :abstain,
        direct: true
      })

    assert Councils.explain(user.author_id, statement.id).effective == :abstain
  end

  test "topic links synchronize only their own membership, in both directions" do
    user = user_fixture()
    a = author_fixture()
    b = author_fixture()
    c = author_fixture()
    {:ok, council} = Councils.ensure(user.author_id)
    topic = hd(council.lists)

    {:ok, topic_public} =
      PeopleLists.create(user, %{
        public: true,
        name: "Policy picks",
        members: [%{author_id: a.id}],
        link_council: true,
        council_list_id: topic.id
      })

    {:ok, general_public} =
      PeopleLists.create(user, %{
        public: true,
        name: "General picks",
        members: [%{author_id: b.id}],
        link_council: true
      })

    assert PeopleLists.linked_list(user, topic.id).id == topic_public.id
    assert PeopleLists.linked_list(user).id == general_public.id
    {:ok, _} = Councils.add_member(user, c.id, topic.id)

    assert Enum.sort(Enum.map(PeopleLists.get(topic_public.id).members, & &1.author_id)) ==
             Enum.sort([a.id, c.id])

    assert Enum.map(PeopleLists.get(general_public.id).members, & &1.author_id) == [b.id]
    topic_public = PeopleLists.get(topic_public.id)

    {:ok, _} =
      PeopleLists.update(user, topic_public.id, %{
        name: topic_public.name,
        version: topic_public.version,
        members: [%{author_id: c.id}]
      })

    council = Councils.get(user.author_id)
    assert Enum.map(hd(council.lists).members, & &1.author_id) == [c.id]
    assert Enum.map(List.last(council.lists).members, & &1.author_id) == [b.id]
    other = user_fixture()

    assert {:error, :invalid_list} =
             PeopleLists.create(other, %{
               public: true,
               name: "Bad link",
               members: [],
               link_council: true,
               council_list_id: topic.id
             })
  end

  test "guest repeated halls survive signup without losing the existing General picks" do
    user = user_fixture()
    a = author_fixture()
    b = author_fixture()
    {:ok, council} = Councils.add_member(user, a.id)
    hall = hd(council.lists).hall_id

    draft = %{
      lists: [
        %{
          name: "Small policy group",
          hall_id: hall,
          members: [%{author_id: b.id, reason: "Careful"}]
        },
        %{name: "Other policy group", hall_id: hall, members: [%{author_id: a.id}]},
        %{name: "General", members: []}
      ]
    }

    assert {:ok, saved} = Draft.apply(user, draft)

    assert Enum.take(Enum.map(saved.lists, & &1.name), 2) == [
             "Small policy group",
             "Other policy group"
           ]

    assert Enum.map(List.last(saved.lists).members, & &1.author_id) == [a.id]
    assert hd(hd(saved.lists).members).reason == "Careful"
  end

  test "final General cannot be moved or deleted and foreign list IDs are rejected" do
    user = user_fixture()
    other = user_fixture()
    {:ok, council} = Councils.ensure(user.author_id)
    {:ok, theirs} = Councils.ensure(other.author_id)
    attrs = Councils.editable(council)

    assert {:error, :invalid_order} =
             Councils.save(user, %{attrs | lists: Enum.reverse(attrs.lists)})

    assert {:error, :invalid_order} =
             Councils.save(user, %{attrs | lists: Enum.drop(attrs.lists, -1)})

    assert {:error, :invalid_order} =
             Councils.save(user, %{
               attrs
               | lists: [hd(Councils.editable(theirs).lists) | attrs.lists]
             })

    assert Repo.get(YouCongress.Councils.List, List.last(council.lists).id)
  end
end
