defmodule YouCongress.DigitalTwins.AI do
  @moduledoc """
  Generate opinions via OpenAI's API.
  """

  @type model_type :: :"gpt-3.5-turbo-0125" | :"gpt-4" | :"gpt-4-1106-preview"

  @models [:"gpt-4-1106-preview", :"gpt-4", :"gpt-3.5-turbo-0125"]
  @token_cost %{
    :"gpt-4-1106-preview" => %{completion_tokens: 0.03, prompt_tokens: 0.01},
    :"gpt-4" => %{completion_tokens: 0.06, prompt_tokens: 0.03},
    :"gpt-3.5-turbo-0125" => %{completion_tokens: 0.002, prompt_tokens: 0.0015}
  }

  @question0 """
  Json data:
  "name": Author name
  "bio": Author bio (max 7 words)
  "agree_rate": Strongly agree/Agree/Disagree/Strongly disagree
  "opinion": Opinion that summarizes why the author agrees or disagrees
  "wikipedia_url": Author wikipedia page URL
  "twitter_username": Author Twitter username
  "country": Author's country

  Topic: Nuclear energy

  Write one opinion in json from a public figure who have publicly shared their views on the topic.
  """

  @answer0 """
  {
    "name": "Naoto Kan",
    "bio": "Former Prime Minister of Japan",
    "agree_rate": "Strongly disagree",
    "opinion": "Nuclear energy is a dangerous and outdated technology. It produces harmful waste and poses a significant risk of accidents or terrorism. We should focus on renewable energy sources instead.",
    "wikipedia_url": "https://en.wikipedia.org/wiki/Elon_Musk",
    "twitter_username": "elonmusk",
    "country": "Japan"
  }
  """

  @answer1 """
  {
    "name": "Angela Merkel",
    "bio": "Chancellor of Germany",
    "agree_rate": "Strongly agree",
    "opinion": "Nuclear energy can play a significant role in reducing carbon emissions and ensuring a stable energy supply. However, safety and waste management must be addressed properly.",
    "wikipedia_url": "https://en.wikipedia.org/wiki/Angela_Merkel",
    "twitter_username": "bundeskanzlerin",
    "country": "Germany"
  }
  """

  @spec generate_opinion(binary, model_type, binary | nil, [binary]) ::
          {:ok, map} | {:error, binary}
  def generate_opinion(topic, model, next_response, exclude_names \\ []) when model in @models do
    question = get_question(topic, next_response, exclude_names)

    with {:ok, data} <- ask_gpt(question, model),
         content <- get_content(data),
         {:ok, opinion} <- Jason.decode(content),
         cost <- get_cost(data, model) do
      {:ok, %{opinion: opinion, cost: cost}}
    else
      {:error, error} -> {:error, error}
    end
  end

  @spec get_question(binary, binary | nil, [binary]) :: binary
  defp get_question(topic, response, exclude_names) do
    exclude_names = Enum.join(exclude_names, ",")

    """
    Topic: #{topic}

    Write one more opinion in first person from a public figure who have publicly shared their views on the topic#{if response, do: " and #{response}"}.

    Exclude opinions from: #{exclude_names}
    """
  end

  @spec ask_gpt(binary, model_type) ::
          {:ok, map} | {:error, binary}
  defp ask_gpt(question, model) do
    OpenAI.chat_completion(
      model: model,
      response_format: %{type: "json_object"},
      messages: [
        %{role: "system", content: "You are a helpful assistant."},
        %{role: "user", content: @question0},
        %{role: "assistant", content: @answer0},
        %{role: "user", content: @question0},
        %{role: "assistant", content: @answer1},
        %{role: "user", content: question}
      ]
    )
  end

  @spec get_content(map) :: [binary]
  defp get_content(data) do
    hd(data.choices)["message"]["content"]
    |> String.split("\n\n")
  end

  @spec get_cost(map, model_type) :: number
  defp get_cost(data, model) do
    completion = data.usage["completion_tokens"] * @token_cost[model][:completion_tokens] / 1000
    prompt = data.usage["prompt_tokens"] * @token_cost[model][:prompt_tokens] / 1000
    completion + prompt
  end
end
