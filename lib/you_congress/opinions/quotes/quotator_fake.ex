defmodule YouCongress.Opinions.Quotes.QuotatorFake do
  @moduledoc """
  Fake implementation that returns 20 plausible quotes with author metadata.
  Used when OPENAI_API_KEY is not configured in dev/test.
  """

  alias YouCongress.Opinions.Quotes.Quotator

  @doc """
  Generate 20 fake quotes for a given question title.
  Returns {:ok, %{quotes: list, cost: 0}} to match the real implementation.
  """
  @spec find_quotes(binary, list(binary)) :: {:ok, %{quotes: list, cost: number}}
  def find_quotes(question_title, exclude_author_names \\ []) do
    quotes =
      1..Quotator.number_of_quotes()
      |> Enum.map(fn _ -> build_quote(question_title) end)
      |> ensure_unique_names(exclude_author_names)

    {:ok, %{quotes: quotes, cost: 0}}
  end

  defp build_quote(question_title) do
    name = Faker.Person.name()

    %{
      "quote" =>
        Faker.Lorem.paragraphs(Enum.random(2..3))
        |> Enum.join(" ")
        |> Kernel.<>(" (re: #{question_title})"),
      "source_url" => Faker.Internet.url(),
      "year" => Integer.to_string(Enum.random(1980..2025)),
      "author" => %{
        "name" => name,
        "bio" => Faker.Lorem.words(5) |> Enum.join(" "),
        # Ensure a valid Wikipedia URL to satisfy Author changeset validations
        "wikipedia_url" => "https://en.wikipedia.org/wiki/" <> wikipedia_title(name),
        "twitter_username" => Faker.Internet.user_name()
      },
      "agree_rate" => Enum.random(["Strongly agree", "Agree", "Disagree", "Strongly disagree"])
    }
  end

  defp wikipedia_title(name) when is_binary(name) do
    name
    |> String.trim()
    |> String.replace(" ", "_")
  end

  defp ensure_unique_names(quotes, excluded) do
    existing = MapSet.new(excluded)

    {unique_quotes, _names} =
      Enum.map_reduce(quotes, existing, fn quote, acc ->
        name = get_in(quote, ["author", "name"]) || ""

        if MapSet.member?(acc, name) do
          new_name = unique_name(acc)
          new_quote = put_in(quote, ["author", "name"], new_name)
          {new_quote, MapSet.put(acc, new_name)}
        else
          {quote, MapSet.put(acc, name)}
        end
      end)

    unique_quotes
  end

  defp unique_name(taken) do
    Stream.repeatedly(fn -> Faker.Person.name() end)
    |> Enum.find(fn n -> not MapSet.member?(taken, n) end)
  end
end
