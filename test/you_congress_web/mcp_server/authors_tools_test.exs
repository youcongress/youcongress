defmodule YouCongressWeb.MCPServer.AuthorsToolsTest do
  use YouCongress.DataCase, async: false

  import Mock
  import YouCongress.AccountsFixtures
  import YouCongress.AuthorsFixtures
  import YouCongress.CountriesFixtures

  alias YouCongress.Accounts
  alias YouCongress.Authors
  alias YouCongressWeb.MCPServer.AuthorsCreate
  alias YouCongressWeb.MCPServer.AuthorsList
  alias YouCongressWeb.MCPServer.AuthorsSearch
  alias YouCongressWeb.MCPServer.AuthorsUpdate

  @missing_key_message "API key is required. Pass ?key=YOUR_KEY in the MCP request URL."
  @invalid_key_message "The provided API key is invalid. Create a new key in Settings > API."
  @create_forbidden_message "Your account is not allowed to create authors."
  @update_forbidden_message "Your account is not allowed to edit this author."
  @not_found_message "Author not found."
  @missing_fields_message "Provide at least one field to update: name, one_line_bio, wikipedia_url, twitter_username, country_id, country."

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

  describe "AuthorsList.execute/2" do
    test "lists authors newest first and paginates with last_id" do
      a1 = author_fixture(name: "Ada Lovelace")
      a2 = author_fixture(name: "Grace Hopper")
      a3 = author_fixture(name: "Alan Turing", twitter_username: "alan_t")

      with_mocked_response(fn ->
        assert {:reply, {:json, %{authors: payload, last_id: last_id}}, :frame} =
                 AuthorsList.execute(%{}, :frame)

        assert Enum.map(payload, & &1.author_id) == [a3.id, a2.id, a1.id]
        assert last_id == a1.id

        assert %{name: "Alan Turing", twitter_username: "alan_t"} = hd(payload)

        assert {:reply, {:json, %{authors: next_page}}, :frame} =
                 AuthorsList.execute(%{last_id: a3.id}, :frame)

        assert Enum.map(next_page, & &1.author_id) == [a2.id, a1.id]
      end)
    end

    test "lists authors in ascending order and paginates with last_id" do
      a1 = author_fixture(name: "Ada Lovelace")
      a2 = author_fixture(name: "Grace Hopper")
      a3 = author_fixture(name: "Alan Turing")

      with_mocked_response(fn ->
        assert {:reply, {:json, %{authors: payload, last_id: last_id}}, :frame} =
                 AuthorsList.execute(%{order: "asc"}, :frame)

        assert Enum.map(payload, & &1.author_id) == [a1.id, a2.id, a3.id]
        assert last_id == a3.id

        assert {:reply, {:json, %{authors: next_page}}, :frame} =
                 AuthorsList.execute(%{order: "asc", last_id: a1.id}, :frame)

        assert Enum.map(next_page, & &1.author_id) == [a2.id, a3.id]
      end)
    end

    test "filters authors by country name or ISO code" do
      spain = country_fixture(name: "Spain", iso_alpha2: "ES", iso_alpha3: "ESP")
      france = country_fixture(name: "France", iso_alpha2: "FR", iso_alpha3: "FRA")
      a1 = author_fixture(name: "Ada Lovelace", country_id: spain.id)
      _a2 = author_fixture(name: "Grace Hopper", country_id: france.id)
      _a3 = author_fixture(name: "Alan Turing", country_id: nil)

      with_mocked_response(fn ->
        assert {:reply, {:json, %{authors: payload}}, :frame} =
                 AuthorsList.execute(%{country: "Spain"}, :frame)

        assert Enum.map(payload, & &1.author_id) == [a1.id]
        assert hd(payload).country == "Spain"

        assert {:reply, {:json, %{authors: payload}}, :frame} =
                 AuthorsList.execute(%{country: "ES"}, :frame)

        assert Enum.map(payload, & &1.author_id) == [a1.id]
      end)
    end

    test "filters authors without a country" do
      spain = country_fixture(name: "Spain", iso_alpha2: "ES", iso_alpha3: "ESP")
      _a1 = author_fixture(name: "Ada Lovelace", country_id: spain.id)
      a2 = author_fixture(name: "Grace Hopper", country_id: nil)

      with_mocked_response(fn ->
        assert {:reply, {:json, %{authors: payload}}, :frame} =
                 AuthorsList.execute(%{without_country: true}, :frame)

        assert Enum.map(payload, & &1.author_id) == [a2.id]
        assert hd(payload).country_id == nil
      end)
    end

    test "lists authors from all countries (including without country) by default" do
      spain = country_fixture(name: "Spain", iso_alpha2: "ES", iso_alpha3: "ESP")
      a1 = author_fixture(name: "Ada Lovelace", country_id: spain.id)
      a2 = author_fixture(name: "Grace Hopper", country_id: nil)

      with_mocked_response(fn ->
        assert {:reply, {:json, %{authors: payload}}, :frame} =
                 AuthorsList.execute(%{without_country: false}, :frame)

        assert Enum.map(payload, & &1.author_id) == [a2.id, a1.id]
      end)
    end

    test "returns an error for an unknown country" do
      with_mocked_response(fn ->
        assert {:reply, {:error, "Unknown country: Atlantis"}, :frame} =
                 AuthorsList.execute(%{country: "Atlantis"}, :frame)
      end)
    end
  end

  describe "AuthorsCreate.execute/2" do
    test "creates an author when authenticated and authorized" do
      admin = admin_fixture()
      api_key = api_key_fixture(admin)
      country = country_fixture(name: "United States", iso_alpha2: "US", iso_alpha3: "USA")

      params = %{
        name: "Dr. Example",
        one_line_bio: "Example bio",
        wikipedia_url: "https://en.wikipedia.org/wiki/Example_person",
        twitter_username: "example_person",
        country: "US"
      }

      with_mocked_response_and_key(api_key.token, fn frame ->
        assert {:reply, {:json, %{author: payload}}, ^frame} =
                 AuthorsCreate.execute(params, frame)

        assert payload.name == "Dr. Example"
        assert payload.one_line_bio == "Example bio"
        assert payload.twitter_username == "example_person"
        assert payload.country_id == country.id
        assert payload.country == "United States"
      end)

      assert [%{twitter_username: "example_person"}] =
               Authors.list_authors(search: "example_person")
    end

    test "returns missing-key error when no API key is provided" do
      with_mocked_response_and_key(nil, fn frame ->
        assert {:reply, {:error, @missing_key_message}, ^frame} =
                 AuthorsCreate.execute(%{one_line_bio: "Dr."}, frame)
      end)
    end

    test "returns invalid-key error when API key token is unknown" do
      with_mocked_response_and_key("invalid", fn frame ->
        assert {:reply, {:error, @invalid_key_message}, ^frame} =
                 AuthorsCreate.execute(%{one_line_bio: "Dr."}, frame)
      end)
    end

    test "returns forbidden when caller cannot create authors" do
      user = user_fixture()
      api_key = api_key_fixture(user)

      with_mocked_response_and_key(api_key.token, fn frame ->
        assert {:reply, {:error, @create_forbidden_message}, ^frame} =
                 AuthorsCreate.execute(%{one_line_bio: "Dr."}, frame)
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

      with_mocked_response_and_key(api_key.token, fn frame ->
        assert {:reply, {:error, message}, ^frame} = AuthorsCreate.execute(params, frame)
        assert message =~ "wikipedia_url must be a valid Wikipedia URL"
      end)
    end
  end

  describe "AuthorsUpdate.execute/2" do
    test "updates an author when authenticated and authorized" do
      admin = admin_fixture()
      api_key = api_key_fixture(admin)
      author = author_fixture(name: "Before", twin_origin: false, bio: "First")
      country = country_fixture(name: "Spain", iso_alpha2: "ES", iso_alpha3: "ESP")

      params = %{
        author_id: author.id,
        name: "After",
        one_line_bio: "Updated",
        country_id: country.id
      }

      with_mocked_response_and_key(api_key.token, fn frame ->
        assert {:reply, {:json, %{author: payload}}, ^frame} =
                 AuthorsUpdate.execute(params, frame)

        assert payload.name == "After"
        assert payload.one_line_bio == "Updated"
        assert payload.country_id == country.id
        assert payload.country == "Spain"
      end)

      updated = Authors.get_author!(author.id)
      assert updated.name == "After"
      assert updated.bio == "Updated"
      assert updated.country_id == country.id
    end

    test "returns an error when no updatable fields are provided" do
      admin = admin_fixture()
      api_key = api_key_fixture(admin)
      author = author_fixture(twin_origin: false)

      with_mocked_response_and_key(api_key.token, fn frame ->
        assert {:reply, {:error, @missing_fields_message}, ^frame} =
                 AuthorsUpdate.execute(%{author_id: author.id}, frame)
      end)
    end

    test "returns missing-key error when no API key is provided" do
      author = author_fixture(twin_origin: false)

      with_mocked_response_and_key(nil, fn frame ->
        assert {:reply, {:error, @missing_key_message}, ^frame} =
                 AuthorsUpdate.execute(%{author_id: author.id, one_line_bio: "Updated"}, frame)
      end)
    end

    test "returns invalid-key error when API key token is unknown" do
      author = author_fixture(twin_origin: false)

      with_mocked_response_and_key("invalid", fn frame ->
        assert {:reply, {:error, @invalid_key_message}, ^frame} =
                 AuthorsUpdate.execute(%{author_id: author.id, one_line_bio: "Updated"}, frame)
      end)
    end

    test "returns forbidden when caller cannot edit authors" do
      user = user_fixture()
      api_key = api_key_fixture(user)
      author = author_fixture(twin_origin: false)

      with_mocked_response_and_key(api_key.token, fn frame ->
        assert {:reply, {:error, @update_forbidden_message}, ^frame} =
                 AuthorsUpdate.execute(%{author_id: author.id, one_line_bio: "Updated"}, frame)
      end)
    end

    test "returns deterministic not-found error for missing author" do
      admin = admin_fixture()
      api_key = api_key_fixture(admin)

      with_mocked_response_and_key(api_key.token, fn frame ->
        assert {:reply, {:error, @not_found_message}, ^frame} =
                 AuthorsUpdate.execute(%{author_id: -1, one_line_bio: "Updated"}, frame)
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

      with_mocked_response_and_key(api_key.token, fn frame ->
        assert {:reply, {:error, message}, ^frame} = AuthorsUpdate.execute(params, frame)
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
       ]}
    ]) do
      frame = Anubis.Server.Frame.new(%{query_params: %{"key" => key}})
      fun.(frame)
    end
  end
end
