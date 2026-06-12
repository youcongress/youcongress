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
      assert SEO.author_description("Jane", []) =~ "Verified quotes and votes from Jane"
    end
  end

  describe "statement_description/3" do
    test "includes quote count and vote split" do
      description =
        SEO.statement_description("Should AI be regulated?", %{for: {2, 67}, against: {1, 33}}, 3)

      assert description =~ "3 verified expert quotes — 67% for, 33% against"
      assert description =~ "Should AI be regulated?"
    end

    test "falls back without quotes" do
      description = SEO.statement_description("Should AI be regulated?", %{}, 0)

      assert description =~ "See expert quotes, votes and sources"
      refute description =~ "% for"
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
