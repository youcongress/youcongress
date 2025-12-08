defmodule YouCongress.OpinionsSearchTest do
  use YouCongress.DataCase

  alias YouCongress.Opinions
  import YouCongress.OpinionsFixtures

  describe "opinions search" do
    test "search returns opinions matching partial words" do
      opinion_fixture(content: "artificial intelligence is the future")
      opinion_fixture(content: "natural intelligence")

      # Should match full word
      assert [match] = Opinions.list_opinions(search: "artificial")
      assert match.content == "artificial intelligence is the future"

      # Should match partial word
      assert [_match] = Opinions.list_opinions(search: "artif")
    end
  end
end
