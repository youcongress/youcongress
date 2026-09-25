defmodule YouCongress.Wikidata.WikidataApiTest do
  use ExUnit.Case, async: true

  alias YouCongress.Wikidata.WikidataApi

  test "rejects attacker-controlled hosts before making a request" do
    urls = [
      "https://127.0.0.1/wiki/Test?.wikipedia.org/wiki/",
      "https://[::1]/wiki/Test",
      "https://evil.example@en.wikipedia.org/wiki/Test",
      "https://en.wikipedia.org.evil.example/wiki/Test",
      "https://en.wikipedia.org:444/wiki/Test"
    ]

    for url <- urls do
      assert WikidataApi.get_wikidata_id(url) == {:error, :invalid_url}
    end
  end
end
