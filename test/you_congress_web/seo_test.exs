defmodule YouCongressWeb.SEOTest do
  use YouCongress.DataCase, async: true

  import Phoenix.LiveViewTest

  alias YouCongressWeb.SEO

  describe "author_title/2" do
    test "uses the most frequent hall as topic" do
      halls = [{"ai-safety", 5}, {"open-source", 2}]

      assert SEO.author_title("Jane Expert", halls) ==
               "What does Jane Expert say about AI Safety? | YouCongress"
    end

    test "skips the generic all/ai halls" do
      halls = [{"all", 9}, {"ai", 7}, {"existential-risk", 3}]

      assert SEO.author_title("Jane Expert", halls) ==
               "What does Jane Expert say about Existential Risk? | YouCongress"
    end

    test "falls back to AI without halls" do
      assert SEO.author_title("Jane Expert", []) ==
               "What does Jane Expert say about AI? | YouCongress"
    end
  end

  describe "author_description/2" do
    test "lists up to three topics" do
      halls = [{"ai-safety", 5}, {"open-source", 3}, {"impact-on-labor", 2}, {"eu", 1}]
      description = SEO.author_description("Jane", halls)

      assert description =~ "AI Safety, Open Source and Impact On Labor"
      refute description =~ "EU"
    end

    test "has a hall-less fallback" do
      assert SEO.author_description("Jane", []) =~ "Sourced quotes and votes from Jane"
    end
  end

  describe "statement_description/3 and /4" do
    test "includes quote count and top wikipedia-linked authors when there are at least 15 quotes" do
      description =
        SEO.statement_description(
          "Should AI be regulated?",
          %{for: {2, 67}, against: {1, 33}},
          38,
          [
            %{
              id: 1,
              name: "Low Reach",
              wikipedia_url: "https://en.wikipedia.org/wiki/Low",
              followers_count: 10
            },
            %{
              id: 2,
              name: "Tim Berners-Lee",
              wikipedia_url: "https://en.wikipedia.org/wiki/Tim_Berners-Lee",
              followers_count: 1000
            },
            %{
              id: 3,
              name: "Cory Doctorow",
              wikipedia_url: "https://en.wikipedia.org/wiki/Cory_Doctorow",
              followers_count: 300
            },
            %{id: 4, name: "No Wiki", wikipedia_url: nil, followers_count: 2000},
            %{
              id: 5,
              name: "Scott Alexander",
              wikipedia_url: "https://en.wikipedia.org/wiki/Scott_Alexander",
              followers_count: 500
            }
          ]
        )

      assert description ==
               "Who's for and against \"Should AI be regulated?\"? 38 sourced quotes including Tim Berners-Lee, Scott Alexander and Cory Doctorow."

      refute description =~ "%"
    end

    test "omits the quote count below 15" do
      description =
        SEO.statement_description(
          "Should AI be regulated?",
          %{for: {2, 67}, against: {1, 33}},
          3,
          [
            %{
              id: 1,
              name: "Tim Berners-Lee",
              wikipedia_url: "https://en.wikipedia.org/wiki/Tim_Berners-Lee",
              followers_count: 1000
            },
            %{
              id: 2,
              name: "Scott Alexander",
              wikipedia_url: "https://en.wikipedia.org/wiki/Scott_Alexander",
              followers_count: 500
            },
            %{
              id: 3,
              name: "Cory Doctorow",
              wikipedia_url: "https://en.wikipedia.org/wiki/Cory_Doctorow",
              followers_count: 300
            }
          ]
        )

      assert description ==
               "Who's for and against \"Should AI be regulated?\"? Sourced quotes including Tim Berners-Lee, Scott Alexander and Cory Doctorow."

      refute description =~ "3 sourced"
      refute description =~ "%"
    end

    test "uses the count fallback only from 15 quotes" do
      description = SEO.statement_description("Should AI be regulated?", %{}, 15, [])

      assert description ==
               "Who's for and against \"Should AI be regulated?\"? 15 sourced quotes from experts and public figures."
    end

    test "falls back without enough quotes or named authors" do
      description = SEO.statement_description("Should AI be regulated?", %{}, 0)

      assert description =~ "See sourced quotes, votes and sources"
      refute description =~ "% for"
      refute description =~ "0 sourced"
    end
  end

  describe "truncate/2" do
    test "keeps short strings intact" do
      assert SEO.truncate("short", 10) == "short"
    end

    test "truncates long strings with an ellipsis" do
      assert SEO.truncate("a very long sentence indeed", 10) == "a very lo…"
    end
  end

  describe "person/2" do
    test "builds a Person with sameAs links" do
      author = %{
        name: "Jane Expert",
        twitter_username: "janex",
        wikipedia_url: "https://en.wikipedia.org/wiki/Jane",
        bio: "AI researcher",
        description: nil,
        profile_image_url: "https://example.com/jane.png"
      }

      person = SEO.person(author, "https://youcongress.org/x/janex")

      assert person["@type"] == "Person"
      assert person["name"] == "Jane Expert"
      assert person["sameAs"] == ["https://x.com/janex", "https://en.wikipedia.org/wiki/Jane"]
      assert person["image"] == "https://example.com/jane.png"
    end

    test "omits empty fields" do
      author = %{
        name: "Jane",
        twitter_username: nil,
        wikipedia_url: nil,
        bio: nil,
        description: nil,
        profile_image_url: nil
      }

      person = SEO.person(author, "url")

      refute Map.has_key?(person, "sameAs")
      refute Map.has_key?(person, "image")
      refute Map.has_key?(person, "description")
    end
  end

  describe "quotation/2" do
    test "keeps structured quote dates in ISO format" do
      opinion = %{
        id: 1,
        content: "A sourced quote",
        source_url: "https://example.com/quote",
        author: %{id: 1, name: "Jane", twitter_username: nil}
      }

      assert SEO.quotation(Map.merge(opinion, %{date: ~D[2026-06-17], date_precision: :day}))[
               "dateCreated"
             ] ==
               "2026-06-17"

      assert SEO.quotation(Map.merge(opinion, %{date: ~D[2026-06-01], date_precision: :month}))[
               "dateCreated"
             ] ==
               "2026-06"

      assert SEO.quotation(Map.merge(opinion, %{date: ~D[2026-01-01], date_precision: :year}))[
               "dateCreated"
             ] ==
               "2026"
    end
  end

  describe "json_ld component" do
    test "escapes </script> in quote content" do
      html =
        render_component(&YouCongressWeb.SEOComponents.json_ld/1,
          data: %{"text" => "evil</script><script>alert(1)"}
        )

      refute html =~ "evil</script>"
      assert html =~ "evil\\u003C\\/script>"
    end
  end
end
