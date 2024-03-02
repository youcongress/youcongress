defmodule YouCongress.Votings.TitleRewording do
  @moduledoc """
  Generate opinions via OpenAI's API.
  """

  alias YouCongress.DigitalTwins.OpenAIModel

  @question """
  Generate three questions from the prompt so:
  - It is short (more like a title) and grammatically correct in English (translate otherwise)
  - It should be a yes/no question which starts with "Should we...", "Shall we...?" or similar
  - It is neutral and not offensive as it's going to be voted and discussed among diverse people.
  - Ideally, it should be about topics that are relevant both locally and globally.
  - Give one option very similar in meaning to the original prompt and two others more creative

  Prompt: Nuclear energy

  The response should be in in JSON format (an array of three strings)
  """

  @answer """
  {
    "questions": [
      "Should we use more nuclear energy?",
      "Is nuclear energy safe?",
      "Would nuclear energy help us tackle climate change?"
    ]
  }
  """

  @spec generate_rewordings(binary, OpenAIModel.t()) :: {:ok, list, number} | {:error, binary}
  def generate_rewordings(prompt, model) do
    with {:ok, data} <- ask_gpt("Prompt: #{prompt}", model),
         content <- OpenAIModel.get_content(data),
         {:ok, %{"questions" => votings}} <- Jason.decode(content),
         cost <- OpenAIModel.get_cost(data, model) do
      {:ok, votings, cost}
    else
      {:error, error} -> {:error, error}
    end
  end

  @spec ask_gpt(binary, OpenAIModel.t()) :: {:ok, map} | {:error, binary}
  defp ask_gpt(question, model) do
    OpenAI.chat_completion(
      model: model,
      response_format: %{type: "json_object"},
      messages: [
        %{role: "system", content: "You are a helpful assistant."},
        %{role: "user", content: @question},
        %{role: "assistant", content: @answer},
        %{role: "user", content: question}
      ]
    )
  end
end
