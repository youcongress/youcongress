defmodule YouCongress.FactCheckerTest do
  use YouCongress.DataCase

  alias YouCongress.FactChecker

  describe "fact_checker" do
    @tag :openai_api
    test "classify_text/1 returns classified text chunks" do
      text = "The Earth is not flat. But it is beautiful."

      assert {:ok, analyzed} = FactChecker.classify_text(text)
      assert is_list(analyzed)

      [first, second] = analyzed
      assert first["text"] == "The Earth is not flat."
      assert first["classification"] == "fact"
      assert second["text"] == "But it is beautiful"
      assert second["classification"] == "opinion"
    end
  end
end
