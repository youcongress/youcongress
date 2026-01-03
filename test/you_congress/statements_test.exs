defmodule YouCongress.StatementsTest do
  use YouCongress.DataCase

  alias YouCongress.Statements

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
  end
end
