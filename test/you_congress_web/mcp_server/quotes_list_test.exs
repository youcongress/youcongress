defmodule YouCongressWeb.MCPServer.QuotesListTest do
  use YouCongress.DataCase, async: false

  import Mock
  import YouCongress.AuthorsFixtures
  import YouCongress.OpinionsFixtures
  import YouCongress.StatementsFixtures
  import YouCongress.VotesFixtures

  alias YouCongressWeb.MCPServer.QuotesList

  describe "execute/2" do
    test "lists quotes newest first with author and vote data" do
      author = author_fixture(name: "Ada Lovelace", bio: "Mathematician")

      q1 =
        opinion_fixture(
          author_id: author.id,
          content: "Quote one",
          source_url: "https://example.com/1",
          year: 2020
        )

      q2 = opinion_fixture(content: "Quote two", source_url: "https://example.com/2")

      # Opinions without a source_url are not quotes
      _not_a_quote = opinion_fixture(source_url: nil)

      statement = statement_fixture()

      vote =
        vote_fixture(%{
          statement_id: statement.id,
          author_id: author.id,
          opinion_id: q1.id,
          answer: :for
        })

      with_mocked_response(fn ->
        assert {:reply, {:json, %{quotes: payload, last_id: last_id}}, :frame} =
                 QuotesList.execute(%{}, :frame)

        assert Enum.map(payload, & &1.opinion_id) == [q2.id, q1.id]
        assert last_id == q1.id

        q1_payload = Enum.find(payload, &(&1.opinion_id == q1.id))
        assert q1_payload.quote == "Quote one"
        assert q1_payload.author == "Ada Lovelace"
        assert q1_payload.author_biography == "Mathematician"
        assert q1_payload.source_url == "https://example.com/1"
        assert q1_payload.year == 2020
        assert q1_payload.verification_status == :unverified
        assert q1_payload.vote_id == vote.id
        assert q1_payload.vote_answer == :for

        q2_payload = Enum.find(payload, &(&1.opinion_id == q2.id))
        assert q2_payload.vote_id == nil
        assert q2_payload.vote_answer == nil
      end)
    end

    test "lists quotes in ascending order and paginates with last_id" do
      q1 = opinion_fixture(content: "One")
      q2 = opinion_fixture(content: "Two")
      q3 = opinion_fixture(content: "Three")

      with_mocked_response(fn ->
        assert {:reply, {:json, %{quotes: payload, last_id: last_id}}, :frame} =
                 QuotesList.execute(%{order: "asc"}, :frame)

        assert Enum.map(payload, & &1.opinion_id) == [q1.id, q2.id, q3.id]
        assert last_id == q3.id

        assert {:reply, {:json, %{quotes: next_page}}, :frame} =
                 QuotesList.execute(%{order: "asc", last_id: q1.id}, :frame)

        assert Enum.map(next_page, & &1.opinion_id) == [q2.id, q3.id]
      end)
    end

    test "paginates with last_id in descending order" do
      q1 = opinion_fixture(content: "One")
      q2 = opinion_fixture(content: "Two")
      q3 = opinion_fixture(content: "Three")

      with_mocked_response(fn ->
        assert {:reply, {:json, %{quotes: payload}}, :frame} =
                 QuotesList.execute(%{last_id: q3.id}, :frame)

        assert Enum.map(payload, & &1.opinion_id) == [q2.id, q1.id]
      end)
    end

    test "returns nil last_id when there are no quotes" do
      with_mocked_response(fn ->
        assert {:reply, {:json, %{quotes: [], last_id: nil}}, :frame} =
                 QuotesList.execute(%{}, :frame)
      end)
    end
  end

  defp with_mocked_response(fun) do
    with_mocks([
      {Anubis.Server.Response, [],
       [
         tool: fn -> :tool end,
         json: fn :tool, data -> {:json, data} end,
         error: fn :tool, message -> {:error, message} end
       ]}
    ]) do
      fun.()
    end
  end
end
