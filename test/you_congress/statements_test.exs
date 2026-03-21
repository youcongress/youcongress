defmodule YouCongress.StatementsTest do
  use YouCongress.DataCase
  use Oban.Testing, repo: YouCongress.Repo

  alias YouCongress.Statements
  import YouCongress.AccountsFixtures

  describe "statements" do
    alias YouCongress.Statements.Statement

    import YouCongress.StatementsFixtures

    @invalid_attrs %{title: nil}

    test "list_statements/0 returns all statements" do
      statement = statement_fixture()
      assert Statements.list_statements() == [statement]
    end

    test "get_statement!/1 returns the statement with given id" do
      statement = statement_fixture()
      assert Statements.get_statement!(statement.id) == statement
    end

    test "create_statement/1 with valid data creates a statement" do
      valid_attrs = %{title: "some title"}

      assert {:ok, %Statement{} = statement} = Statements.create_statement(valid_attrs)
      assert statement.title == "some title"
    end

    test "create_statement/1 with invalid data returns error changeset" do
      assert {:error, %Ecto.Changeset{}} = Statements.create_statement(@invalid_attrs)
    end

    test "create_statement/1 does not enqueue a quote job automatically" do
      user = admin_fixture()

      Oban.Testing.with_testing_mode(:manual, fn ->
        assert {:ok, %Statement{} = _statement} =
                 Statements.create_statement(%{title: "Auto quote me", user_id: user.id})

        refute_enqueued(worker: YouCongress.Workers.QuotatorWorker)
      end)
    end

    test "update_statement/2 with valid data updates the statement" do
      statement = statement_fixture()
      update_attrs = %{title: "some updated title"}

      assert {:ok, %Statement{} = statement} =
               Statements.update_statement(statement, update_attrs)

      assert statement.title == "some updated title"
    end

    test "update_statement/2 with invalid data returns error changeset" do
      statement = statement_fixture()
      assert {:error, %Ecto.Changeset{}} = Statements.update_statement(statement, @invalid_attrs)
      assert statement == Statements.get_statement!(statement.id)
    end

    test "delete_statement/1 deletes the statement" do
      statement = statement_fixture()
      assert {:ok, %Statement{}} = Statements.delete_statement(statement)
      assert_raise Ecto.NoResultsError, fn -> Statements.get_statement!(statement.id) end
    end

    test "change_statement/1 returns a statement changeset" do
      statement = statement_fixture()
      assert %Ecto.Changeset{} = Statements.change_statement(statement)
    end

    test "create_statement/1 uses provided slug when it doesn't exist" do
      assert {:ok, %Statement{} = statement} =
               Statements.create_statement(%{title: "Build a CERN for AI", slug: "build-cern-ai"})

      assert statement.slug == "build-cern-ai"
    end

    test "create_statement/1 appends number to slug when it already exists" do
      statement_fixture(%{title: "First statement", slug: "build-cern-ai"})

      assert {:ok, %Statement{} = statement} =
               Statements.create_statement(%{title: "Build a CERN for AI", slug: "build-cern-ai"})

      assert statement.slug == "build-cern-ai2"
    end

    test "create_statement/1 increments slug number until unique" do
      statement_fixture(%{title: "First", slug: "my-slug"})
      statement_fixture(%{title: "Second", slug: "my-slug2"})
      statement_fixture(%{title: "Third", slug: "my-slug3"})

      assert {:ok, %Statement{} = statement} =
               Statements.create_statement(%{title: "Fourth", slug: "my-slug"})

      assert statement.slug == "my-slug4"
    end

    test "update_statement/2 preserves existing slug when slug is not changed" do
      statement = statement_fixture(%{slug: "original-slug"})

      assert {:ok, %Statement{} = updated} =
               Statements.update_statement(statement, %{title: "Updated title"})

      assert updated.slug == "original-slug"
    end
  end
end
