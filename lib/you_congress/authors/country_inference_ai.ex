defmodule YouCongress.Authors.CountryInferenceAI do
  @moduledoc """
  Uses an LLM to infer an author's country from local profile details.
  """

  alias YouCongress.Authors.Author
  alias YouCongress.Authors.CountryInference
  alias YouCongress.DigitalTwins.OpenAIModel

  @behaviour CountryInference

  @impl CountryInference
  @spec infer_country(Author.t(), OpenAIModel.t()) ::
          {:ok, CountryInference.result()} | {:error, binary()}
  def infer_country(%Author{} = author, model) do
    with {:ok, data} <- ask_gpt(prompt(author), model),
         content when is_binary(content) <- OpenAIModel.get_content(data),
         {:ok, response} <- Jason.decode(content) do
      {:ok, normalize_response(response)}
    else
      {:error, error} -> {:error, error}
      error -> {:error, "Failed to infer author country: #{inspect(error)}"}
    end
  end

  @spec ask_gpt(binary(), OpenAIModel.t()) :: {:ok, map()} | {:error, binary()}
  defp ask_gpt(prompt, model) do
    OpenAI.chat_completion(
      model: model,
      response_format: %{
        type: "json_schema",
        json_schema: %{
          name: "AuthorCountryInference",
          strict: true,
          schema: json_schema()
        }
      },
      messages: [
        %{
          role: "system",
          content: """
          You infer a public author profile's country from supplied local details only.
          Return should_update=false unless the country is clear from the bio, description, location, username, Wikipedia URL, or a well-known public office/organization in the details.
          Do not infer country from a culturally associated name alone.
          """
        },
        %{role: "user", content: prompt}
      ]
    )
  end

  defp prompt(%Author{} = author) do
    """
    Decide whether YouCongress should set this author's country.

    Rules:
    - Set should_update=true only when the details make one country clear.
    - Use the country where the person or organization is primarily associated, represents, or is based.
    - If location is vague, global, fictional, multi-country, or ambiguous, do not update.
    - If details conflict or only suggest a region/continent, do not update.
    - Return a country name or ISO 3166-1 alpha-2 code in country. Use an empty string when should_update is false.

    Author details:
    Name: #{field(author.name)}
    Bio: #{field(author.bio)}
    Description: #{field(author.description)}
    Location: #{field(author.location)}
    Wikipedia URL: #{field(author.wikipedia_url)}
    X username: #{field(author.twitter_username)}
    """
  end

  defp json_schema do
    %{
      type: "object",
      additionalProperties: false,
      properties: %{
        "should_update" => %{
          type: "boolean",
          description: "Whether the country is clear enough to update."
        },
        "country" => %{
          type: "string",
          description:
            "Country name or ISO 3166-1 alpha-2 code. Empty string when should_update is false."
        },
        "reason" => %{
          type: "string",
          description: "Short reason based only on the supplied details."
        }
      },
      required: ["should_update", "country", "reason"]
    }
  end

  defp normalize_response(%{
         "should_update" => should_update,
         "country" => country,
         "reason" => reason
       }) do
    %{
      should_update: should_update == true,
      country: normalize_country(country),
      reason: reason
    }
  end

  defp normalize_response(_response), do: %{should_update: false, country: nil, reason: nil}

  defp normalize_country(country) when is_binary(country) do
    country
    |> String.trim()
    |> case do
      "" -> nil
      country -> country
    end
  end

  defp normalize_country(_), do: nil

  defp field(value) when is_binary(value) do
    value
    |> String.trim()
    |> case do
      "" -> "(blank)"
      value -> value
    end
  end

  defp field(_), do: "(blank)"
end
