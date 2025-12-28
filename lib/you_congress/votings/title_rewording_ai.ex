defmodule YouCongress.Votings.TitleRewordingAI do
  @moduledoc """
  Generate opinions via OpenAI's API.
  """

  alias YouCongress.DigitalTwins.OpenAIModel

  @prompt """
  Generate three questions from the prompt so:
  - The first one should be exactly the prompt but with correct grammar and affirmative (not a question) and translated to English if it was in a different language.
  - The others should be more creative, short (more like a title) and, also, grammatically correct in English. Translate to English if it's in a different language.
  - These last two may be titles such as "Build a CERN for AI" or "Carbon tax" instead of yes/no questions which starts with "Should we...", "Shall we...?" or similar
  - They are neutral and not offensive as it's going to be voted and discussed among diverse people.
  - Ideally, they should be about topics that are relevant both locally and globally.

  Prompt: Nuclear energy

  The response should be in JSON format (an array of three strings)
  """

  @answer """
  {
    "questions": [
      "Build a CERN for AI",
      "Carbon tax",
      "Space exploration"
    ]
  }
  """

  @spec generate_rewordings(binary, OpenAIModel.t()) :: {:ok, list, number} | {:error, binary}
  def generate_rewordings(prompt, model) do
    with {:ok, data} <- ask_gpt("Prompt: #{prompt}", model),
         content when is_binary(content) <- OpenAIModel.get_content(data),
         {:ok, %{"questions" => votings}} <- Jason.decode(content),
         cost <- OpenAIModel.get_cost(data, model) do
      {:ok, votings, cost}
    else
      {:error, error} -> {:error, error}
      error -> {:error, "Failed to process OpenAI response: #{inspect(error)}"}
    end
  end

  @spec ask_gpt(binary, OpenAIModel.t()) :: {:ok, map} | {:error, binary}
  defp ask_gpt(prompt, model) do
    OpenAI.chat_completion(
      model: model,
      response_format: %{
        type: "json_schema",
        json_schema: %{
          name: "TitleRewordingResult",
          strict: true,
          schema: json_schema()
        }
      },
      messages: [
        %{role: "system", content: "You are a helpful assistant."},
        %{role: "user", content: @prompt},
        %{role: "assistant", content: @answer},
        %{role: "user", content: prompt}
      ]
    )
  end

  defp json_schema do
    %{
      type: "object",
      additionalProperties: false,
      properties: %{
        "questions" => %{
          type: "array",
          description: "Array of 3 policy title suggestions based on the user's prompt",
          minItems: 3,
          maxItems: 3,
          items: %{
            type: "string",
            description:
              "The first should be exactly the original but in correct English. The others should be creative, short (more like a title) and, also, grammatically correct in English."
          }
        }
      },
      required: ["questions"]
    }
  end
end
