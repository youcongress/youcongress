defmodule YouCongress.Votings.TitleRewording do
  @moduledoc """
  Generate opinions via OpenAI's API.
  """

  @type model_type :: :"gpt-3.5-turbo" | :"gpt-4" | :"gpt-4-1106-preview"

  @models [:"gpt-4-1106-preview", :"gpt-4", :"gpt-3.5-turbo"]
  @token_cost %{
    :"gpt-4-1106-preview" => %{completion_tokens: 0.03, prompt_tokens: 0.01},
    :"gpt-4" => %{completion_tokens: 0.06, prompt_tokens: 0.03},
    :"gpt-3.5-turbo" => %{completion_tokens: 0.002, prompt_tokens: 0.0015}
  }

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

  @spec generate_rewordings(binary, model_type) :: {:ok, list, number} | {:error, binary}
  def generate_rewordings(prompt, model) when model in @models do
    with {:ok, data} <- ask_gpt("Prompt: #{prompt}", model),
         content <- get_content(data),
         {:ok, %{"questions" => votings}} <- Jason.decode(content),
         cost <- get_cost(data, model) do
      {:ok, votings, cost}
    else
      {:error, error} -> {:error, error}
    end
  end

  @spec ask_gpt(binary, model_type) ::
          {:ok, map} | {:error, binary}
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
