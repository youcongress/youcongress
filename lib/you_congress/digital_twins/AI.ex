defmodule YouCongress.DigitalTwins.AI do
  @models [:"gpt-4", :"gpt-3.5-turbo"]
  @token_cost %{
    :"gpt-4" => %{completion_tokens: 0.06, prompt_tokens: 0.03},
    :"gpt-3.5-turbo" => %{completion_tokens: 0.002, prompt_tokens: 0.0015}
  }

  @question0 """
  Json data:
  "name": Author name
  "bio": Author bio (max 7 words)
  "agree_rate": Strongly agree/Agree/Abstain/Disagree/Strongly disagree
  "opinion": Opinion that summarizes why the author agrees or disagrees
  "year": Last year the author expressed their opinion on the topic
  "wikipedia_url": Author wikipedia page URL
  "twitter_url": Author Twitter URL
  "model_rate": Percentage you believe the opinion represents the view of the person (0%: no idea as there is no real overall views and attitude from the author, 100%: there is a real quote)
  "model_opinion": "Notes about the percentage
  "country": Author's country

  Topic: Nuclear energy

  Write one opinions in json from a public figure who have publicly shared their views on the topic.
  """

  @answer0 """
  {
    "name": "Elon Musk",
    "bio": "CEO of Tesla and SpaceX",
    "agree_rate": "Strongly disagree",
    "opinion": "Nuclear energy is a dangerous and outdated technology. It produces harmful waste and poses a significant risk of accidents or terrorism. We should focus on renewable energy sources instead.",
    "year": 2013,
    "wikipedia_url": "https://en.wikipedia.org/wiki/Elon_Musk",
    "twitter_url": "https://twitter.com/elonmusk",
    "model_rate": "90%",
    "model_opinion": "Musk has been a vocal critic of nuclear energy",
    "country": "United States"
  }
  """

  @spec generate_opinion(binary, :"gpt-3.5-turbo" | :"gpt-4", [binary]) ::
          {:ok, map} | {:error, binary}
  def generate_opinion(topic, model, exclude_names \\ []) when model in @models do
    question = get_question(topic, exclude_names)

    with {:ok, data} <- ask_gpt(question, model),
         content <- get_content(data),
         {:ok, opinion} <- Jason.decode(content),
         cost <- get_cost(data, model) do
      {:ok, %{opinion: opinion, cost: cost}}
    else
      {:error, error} -> {:error, error}
    end
  end

  @spec get_question(binary, [binary]) :: binary
  defp get_question(topic, exclude_names) do
    exclude_names = Enum.join(exclude_names, ",")

    """
    Topic: #{topic}

    Write one more opinion from public figures who have publicly shared their views on the topic.

    Exclude opinions from: #{exclude_names}
    """
  end

  @spec ask_gpt(binary, :"gpt-3.5-turbo" | :"gpt-4") :: {:ok, map} | {:error, binary}
  defp ask_gpt(question, model) do
    OpenAI.chat_completion(
      model: model,
      messages: [
        %{role: "system", content: "You are a helpful assistant."},
        %{role: "user", content: @question0},
        %{role: "assistant", content: @answer0},
        %{role: "user", content: question}
      ]
    )
  end

  @spec get_content(map) :: [binary]
  defp get_content(data) do
    hd(data.choices)["message"]["content"]
    |> String.split("\n\n")
  end

  @spec get_cost(map, :"gpt-3.5-turbo" | :"gpt-4") :: number
  defp get_cost(data, model) do
    completion = data.usage["completion_tokens"] * @token_cost[model][:completion_tokens] / 1000
    prompt = data.usage["prompt_tokens"] * @token_cost[model][:prompt_tokens] / 1000
    completion + prompt
  end
end
