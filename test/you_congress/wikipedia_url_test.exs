defmodule YouCongress.WikipediaUrlTest do
  use ExUnit.Case, async: true

  alias YouCongress.WikipediaUrl

  test "accepts canonical article URLs on language Wikipedia hosts" do
    assert {:ok, %{host: "en.wikipedia.org", title: "Douglas_Adams"}} =
             WikipediaUrl.parse("https://en.wikipedia.org/wiki/Douglas_Adams")

    assert WikipediaUrl.valid?("https://simple.wikipedia.org/wiki/Computer_science")
    assert WikipediaUrl.valid?("https://zh-min-nan.wikipedia.org/wiki/Tai-oan")
  end

  test "rejects non-Wikipedia and ambiguous authorities" do
    invalid_urls = [
      "http://en.wikipedia.org/wiki/Test",
      "https://127.0.0.1/wiki/Test?.wikipedia.org/wiki/",
      "https://10.0.0.1/.wikipedia.org/wiki/Test",
      "https://en.wikipedia.org.evil.example/wiki/Test",
      "https://wikipedia.org.evil.example/wiki/Test",
      "https://evil.example@en.wikipedia.org/wiki/Test",
      "https://en.wikipedia.org:444/wiki/Test",
      "https://en.wikipedia.org./wiki/Test",
      "https://en.wikipedia.org/not-wiki/Test",
      "https://en.wikipedia.org/wiki/",
      "https://en.wikipedia.org/wiki/Test?redirect=https://127.0.0.1",
      "https://en.wikipedia.org/wiki/Test#fragment",
      "https://en.wikipedia.org/wiki/%ZZ",
      "https://[::1]/wiki/Test"
    ]

    for url <- invalid_urls do
      assert WikipediaUrl.parse(url) == {:error, :invalid_url}, url
    end
  end
end
