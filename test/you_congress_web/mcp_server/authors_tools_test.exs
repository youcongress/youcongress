defmodule YouCongressWeb.MCPServer.AuthorsToolsTest do
  use YouCongress.DataCase, async: false

  import Mock
  import YouCongress.AccountsFixtures
  import YouCongress.AuthorsFixtures

  alias YouCongress.Accounts
  alias YouCongress.Authors
  alias YouCongressWeb.MCPServer.AuthorsCreate
  alias YouCongressWeb.MCPServer.AuthorsSearch
  alias YouCongressWeb.MCPServer.AuthorsUpdate

  @missing_key_message "API key is required. Pass ?key=YOUR_KEY in the MCP request URL."
  @invalid_key_message "The provided API key is invalid. Create a new key in Settings > API."
  @create_forbidden_message "Your account is not allowed to create authors."
  @update_forbidden_message "Your account is not allowed to edit this author."
  @not_found_message "Author not found."
  @missing_fields_message "Provide at least one field to update: name, one_line_bio, wikipedia_url, twitter_username, country."

  describe "AuthorsSearch.execute/2" do
    test "returns serialized author matches" do
      target = author_fixture(name: "Ada Lovelace", twitter_username: "ada_l")
      _other = author_fixture(name: "Grace Hopper", twitter_username: "amazing_grace")

      with_mocked_response(fn ->
        assert {:reply, {:json, %{matches: [payload]}}, :frame} =
                 AuthorsSearch.execute(%{query: "Lovelace"}, :frame)

        assert payload.author_id == target.id
        assert payload.name == "Ada Lovelace"
        assert payload.twitter_username == "ada_l"
      end)
    end
  end

  describe "AuthorsCreate.execute/2" do
    test "creates an author when authenticated and authorized" do
      admin = admin_fixture()
      api_key = api_key_fixture(admin)

      params = %{
        name: "Dr. Example",
        one_line_bio: "Example bio",
        wikipedia_url: "https://en.wikipedia.org/wiki/Example_person",
        twitter_username: "example_person",
        country: "Wonderland"
      }

      with_mocked_response_and_key(api_key.token, fn ->
        assert {:reply, {:json, %{author: payload}}, :frame} =
                 AuthorsCreate.execute(params, :frame)

        assert payload.name == "Dr. Example"
        assert payload.one_line_bio == "Example bio"
        assert payload.twitter_username == "example_person"
        assert payload.country == "Wonderland"
      end)

      assert [%{twitter_username: "example_person"}] =
               Authors.list_authors(search: "example_person")
    end

    test "returns missing-key error when no API key is provided" do
      with_mocked_response_and_key(nil, fn ->
        assert {:reply, {:error, @missing_key_message}, :frame} =
                 AuthorsCreate.execute(%{one_line_bio: "Dr."}, :frame)
      end)
    end

    test "returns invalid-key error when API key token is unknown" do
      with_mocked_response_and_key("invalid", fn ->
        assert {:reply, {:error, @invalid_key_message}, :frame} =
                 AuthorsCreate.execute(%{one_line_bio: "Dr."}, :frame)
      end)
    end

    test "returns forbidden when caller cannot create authors" do
      user = user_fixture()
      api_key = api_key_fixture(user)

      with_mocked_response_and_key(api_key.token, fn ->
        assert {:reply, {:error, @create_forbidden_message}, :frame} =
                 AuthorsCreate.execute(%{one_line_bio: "Dr."}, :frame)
      end)
    end

    test "returns validation errors from the context" do
      admin = admin_fixture()
      api_key = api_key_fixture(admin)

      params = %{
        name: "Bad URL",
        one_line_bio: "Bio",
        wikipedia_url: "https://example.com/not_wiki"
      }

      with_mocked_response_and_key(api_key.token, fn ->
        assert {:reply, {:error, message}, :frame} = AuthorsCreate.execute(params, :frame)
        assert message =~ "wikipedia_url must be a valid Wikipedia URL"
      end)
    end
  end

  describe "AuthorsUpdate.execute/2" do
    test "updates an author when authenticated and authorized" do
      admin = admin_fixture()
      api_key = api_key_fixture(admin)
      author = author_fixture(name: "Before", twin_origin: false, bio: "First")

      params = %{
        author_id: author.id,
        name: "After",
        one_line_bio: "Updated"
      }

      with_mocked_response_and_key(api_key.token, fn ->
        assert {:reply, {:json, %{author: payload}}, :frame} =
                 AuthorsUpdate.execute(params, :frame)

        assert payload.name == "After"
        assert payload.one_line_bio == "Updated"
      end)

      updated = Authors.get_author!(author.id)
      assert updated.name == "After"
      assert updated.bio == "Updated"
    end

    test "returns an error when no updatable fields are provided" do
      admin = admin_fixture()
      api_key = api_key_fixture(admin)
      author = author_fixture(twin_origin: false)

      with_mocked_response_and_key(api_key.token, fn ->
        assert {:reply, {:error, @missing_fields_message}, :frame} =
                 AuthorsUpdate.execute(%{author_id: author.id}, :frame)
      end)
    end

    test "returns missing-key error when no API key is provided" do
      author = author_fixture(twin_origin: false)

      with_mocked_response_and_key(nil, fn ->
        assert {:reply, {:error, @missing_key_message}, :frame} =
                 AuthorsUpdate.execute(%{author_id: author.id, one_line_bio: "Updated"}, :frame)
      end)
    end

    test "returns invalid-key error when API key token is unknown" do
      author = author_fixture(twin_origin: false)

      with_mocked_response_and_key("invalid", fn ->
        assert {:reply, {:error, @invalid_key_message}, :frame} =
                 AuthorsUpdate.execute(%{author_id: author.id, one_line_bio: "Updated"}, :frame)
      end)
    end

    test "returns forbidden when caller cannot edit authors" do
      user = user_fixture()
      api_key = api_key_fixture(user)
      author = author_fixture(twin_origin: false)

      with_mocked_response_and_key(api_key.token, fn ->
        assert {:reply, {:error, @update_forbidden_message}, :frame} =
                 AuthorsUpdate.execute(%{author_id: author.id, one_line_bio: "Updated"}, :frame)
      end)
    end

    test "returns deterministic not-found error for missing author" do
      admin = admin_fixture()
      api_key = api_key_fixture(admin)

      with_mocked_response_and_key(api_key.token, fn ->
        assert {:reply, {:error, @not_found_message}, :frame} =
                 AuthorsUpdate.execute(%{author_id: -1, one_line_bio: "Updated"}, :frame)
      end)
    end

    test "returns validation errors from the context" do
      admin = admin_fixture()
      api_key = api_key_fixture(admin)
      author = author_fixture(twin_origin: false)

      params = %{
        author_id: author.id,
        wikipedia_url: "http://example.org/wiki/Person"
      }

      with_mocked_response_and_key(api_key.token, fn ->
        assert {:reply, {:error, message}, :frame} = AuthorsUpdate.execute(params, :frame)
        assert message =~ "wikipedia_url must start with https://"
      end)
    end
  end

  defp api_key_fixture(user) do
    {:ok, api_key} = Accounts.create_api_key_for_user(user, %{"name" => "CLI", "scope" => :write})
    api_key
  end

  defp with_mocked_response(fun) do
    with_mocks([
      {Anubis.Server.Response, [],
       [
         tool: fn -> :tool end,
         json: fn :tool, data -> {:json, data} end,
         error: fn :tool, message -> {:error, message} end
       ]},
      {Anubis.Server.Frame, [],
       [
         get_query_param: fn _frame, _key -> nil end
       ]}
    ]) do
      fun.()
    end
  end

  defp with_mocked_response_and_key(key, fun) do
    with_mocks([
      {Anubis.Server.Response, [],
       [
         tool: fn -> :tool end,
         json: fn :tool, data -> {:json, data} end,
         error: fn :tool, message -> {:error, message} end
       ]},
      {Anubis.Server.Frame, [],
       [
         get_query_param: fn _frame, "key" -> key end
       ]}
    ]) do
      fun.()
    end
  end
end
