defmodule YouCongress.Votes.Answers.AnswerTest do
  use ExUnit.Case
  alias YouCongress.Votes.Answers.Answer

  describe "changeset/2" do
    test "valid attrs" do
      answer = %Answer{}
      attrs = %{"response" => "Strongly agree"}

      changeset = Answer.changeset(answer, attrs)

      assert changeset.valid?
      assert changeset.params == attrs
    end

    test "missing response" do
      answer = %Answer{}
      attrs = %{}

      changeset = Answer.changeset(answer, attrs)

      refute changeset.valid?
      assert changeset.errors == [response: {"can't be blank", [{:validation, :required}]}]
    end
  end
end
