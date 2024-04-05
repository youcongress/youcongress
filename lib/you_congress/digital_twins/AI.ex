defmodule YouCongress.DigitalTwins.AI do
  @moduledoc """
  Generate opinions via OpenAI's API.
  """

  alias YouCongress.DigitalTwins.OpenAIModel

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

  @spec generate_opinion(binary, OpenAIModel.t(), binary | nil, [binary]) ::
          {:ok, map} | {:error, binary}
  def generate_opinion(topic, model, next_response, name) do
    question = get_question(topic, next_response, name)

    with {:ok, data} <- ask_gpt(question, model),
         content <- OpenAIModel.get_content(data),
         {:ok, opinion} <- Jason.decode(content),
         cost <- OpenAIModel.get_cost(data, model) do
      {:ok, %{opinion: opinion, cost: cost}}
    else
      {:error, error} -> {:error, error}
    end
  end

  @spec get_question(binary, binary | nil, [binary]) :: binary
  defp get_question(topic, response, name) do
    """
    Topic: #{topic}

    Write one more opinion in first person from the public figure "#{name}".
    #{if response, do: "Consider that #{name} must #{response} with the question #{topic}. Write the opinion accordingly."}.
    It should be plausible that the public figure has that opinion about the topic (E.g. most actors won't have an opinion on programming languages)
    """
  end

  @spec ask_gpt(binary, OpenAIModel.t()) ::
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
end
