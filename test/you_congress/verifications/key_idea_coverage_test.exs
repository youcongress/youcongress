defmodule YouCongress.Verifications.KeyIdeaCoverageTest do
  use ExUnit.Case, async: true

  alias YouCongress.Verifications.KeyIdeaCoverage

  defp complete_coverage(attrs \\ %{}) do
    Map.merge(
      %{
        "all_key_ideas_covered" => true,
        "key_idea_coverage" => [
          %{"idea" => "internal deployment", "evidence" => "before internal deployment"}
        ],
        "missing_key_ideas" => []
      },
      attrs
    )
  end

  test "requires an explicit complete flag and non-empty quote evidence" do
    assert KeyIdeaCoverage.valid?(complete_coverage())
    refute KeyIdeaCoverage.valid?(complete_coverage(%{"all_key_ideas_covered" => false}))
    refute KeyIdeaCoverage.valid?(complete_coverage(%{"key_idea_coverage" => []}))

    refute KeyIdeaCoverage.valid?(
             complete_coverage(%{
               "key_idea_coverage" => [%{"idea" => "internal deployment", "evidence" => ""}]
             })
           )
  end

  test "requires claimed evidence to occur in the quote when quote text is supplied" do
    assert KeyIdeaCoverage.valid?(
             complete_coverage(),
             "Labs should run assessments before internal deployment."
           )

    refute KeyIdeaCoverage.valid?(
             complete_coverage(),
             "Labs should run assessments before public deployment."
           )
  end

  test "rejects coverage when the model reports a missing material idea" do
    refute KeyIdeaCoverage.valid?(
             complete_coverage(%{"missing_key_ideas" => ["high-stakes use"]})
           )
  end

  test "downgrades an accepted relevance result with incomplete coverage" do
    result =
      KeyIdeaCoverage.enforce_verification_result("relevance", %{
        "status" => "ai_verified",
        "comment" => "The quote discusses deployment.",
        "all_key_ideas_covered" => false,
        "key_idea_coverage" => [
          %{"idea" => "deployment", "evidence" => "before deployment"}
        ],
        "missing_key_ideas" => ["internal deployment"]
      })

    assert result["status"] == "disputed"
    assert result["comment"] =~ "not every material key idea"
  end

  test "changes a vote result to none when coverage is incomplete" do
    result =
      KeyIdeaCoverage.enforce_verification_result("vote", %{
        "correct_answer" => "for",
        "comment" => "The quote favors evaluations.",
        "all_key_ideas_covered" => false,
        "key_idea_coverage" => [
          %{"idea" => "risk evaluations", "evidence" => "safety evaluations"}
        ],
        "missing_key_ideas" => ["internal deployment"]
      })

    assert result["correct_answer"] == "none"
    assert result["comment"] =~ "No vote accepted"
  end
end
