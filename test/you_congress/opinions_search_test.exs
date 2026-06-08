defmodule YouCongress.OpinionsSearchTest do
  use YouCongress.DataCase

  import Mock
  alias YouCongress.Opinions
  alias YouCongress.Embeddings

  import YouCongress.OpinionsFixtures

  @embedding_dimensions 1536

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

  describe "get_by_content_similarity/1" do
    test "returns an empty list for blank input" do
      assert Opinions.get_by_content_similarity(" \n\t") == []
    end

    test "returns sourced quotes with embeddings ordered by nearest cosine match" do
      near_quote =
        opinion_fixture(
          content: "closest quote",
          content_embedding: embedding([1.0, 0.0, 0.0])
        )

      far_quote =
        opinion_fixture(
          content: "farther quote",
          content_embedding: embedding([0.0, 1.0, 0.0])
        )

      opinion_fixture(content: "quote without embedding")

      opinion_fixture(
        content: "unsourced opinion with embedding",
        source_url: nil,
        content_embedding: embedding([1.0, 0.0, 0.0])
      )

      with_mock Embeddings, embed: fn "query text" -> {:ok, embedding([1.0, 0.0, 0.0])} end do
        assert [first, second] = Opinions.get_by_content_similarity("query text")
        assert [first.id, second.id] == [near_quote.id, far_quote.id]
      end
    end

    test "returns an empty list when query embedding generation fails" do
      with_mock Embeddings, embed: fn "query text" -> {:error, :boom} end do
        assert Opinions.get_by_content_similarity("query text") == []
      end
    end
  end

  defp embedding(values) do
    values ++ List.duplicate(0.0, @embedding_dimensions - length(values))
  end
end
