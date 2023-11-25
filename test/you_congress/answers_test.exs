defmodule YouCongress.Votes.AnswersTest do
  use YouCongress.DataCase

  alias YouCongress.Votes.Answers

  describe "answers" do
    alias YouCongress.Votes.Answers.Answer

    import YouCongress.Votes.AnswersFixtures

    @invalid_attrs %{
      response: nil
    }

    test "list_answers/0 returns all answers" do
      assert Enum.sort(Answers.basic_responses()) ==
               Answers.list_answers()
               |> Enum.map(fn answer -> answer.response end)
               |> Enum.sort()
    end

    test "get_answer!/1 returns the answer with given id" do
      answer = answer_fixture()
      assert Answers.get_answer!(answer.id) == answer
    end

    test "create_answer/1 with valid data creates an answer" do
      valid_attrs = %{
        response: "Strongly Agree"
      }

      assert {:ok, %Answer{} = answer} = Answers.create_answer(valid_attrs)
      assert answer.response == "Strongly Agree"
    end

    test "create_answer/1 with invalid data returns error changeset" do
      assert {:error, %Ecto.Changeset{}} = Answers.create_answer(@invalid_attrs)
    end

    test "update_answer/2 with valid data updates the answer" do
      answer = answer_fixture()

      update_attrs = %{
        response: "Disagree"
      }

      assert {:ok, %Answer{} = answer} = Answers.update_answer(answer, update_attrs)
      assert answer.response == "Disagree"
    end

    test "update_answer/2 with invalid data returns error changeset" do
      answer = answer_fixture()
      assert {:error, %Ecto.Changeset{}} = Answers.update_answer(answer, @invalid_attrs)
      assert answer == Answers.get_answer!(answer.id)
    end

    test "delete_answer/1 deletes the answer" do
      answer = answer_fixture()
      assert {:ok, %Answer{}} = Answers.delete_answer(answer)
      assert_raise Ecto.NoResultsError, fn -> Answers.get_answer!(answer.id) end
    end

    test "change_answer/1 returns an answer changeset" do
      answer = answer_fixture()
      assert %Ecto.Changeset{} = Answers.change_answer(answer)
    end

    test "get_random_answer/0 returns a random answer" do
      assert %Answer{} = Answers.get_random_answer()
    end
  end
end
