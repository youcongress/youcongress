defmodule YouCongress.Halls.Classification do
  @moduledoc """
  Generate the tags (halls) for a statement
  """

  alias YouCongress.DigitalTwins.OpenAIModel

  @answer0 """
  {
    "main_tag": "ai",
    "other_tags": ["spain"]
  }
  """

  @json_schema %{
    name: "classification",
    strict: true,
    schema: %{
      type: "object",
      properties: %{
        main_tag: %{
          type: "string",
          description: "The most relevant tag"
        },
        other_tags: %{
          type: "array",
          items: %{type: "string"},
          description: "Other relevant tags"
        }
      },
      required: ["main_tag", "other_tags"],
      additionalProperties: false
    }
  }

  @behaviour YouCongress.Halls.ClassificationBehaviour

  @impl YouCongress.Halls.ClassificationBehaviour
  @spec classify(binary, OpenAIModel.t()) :: {:ok, map} | {:error, binary}
  def classify(text, model) do
    text = """
    Possible tags:
    #{YouCongress.Halls.Hall.names_str()}

    Classify the following question and return the most relevant tag as "main_tag" and other relevant tags as "other_tags" array in json format:

    Question:#{text}
    """

    case classify_gpt(text, model) do
      {:ok, %{main_tag: main_tag, other_tags: other_tags, cost: cost}} ->
        {:ok, %{main_tag: main_tag, other_tags: other_tags, cost: cost}}

      {:error, error} ->
        {:error, error}
    end
  end

  @spec classify_gpt(binary, OpenAIModel.t()) :: {:ok, map} | {:error, binary}
  defp classify_gpt(text, model) do
    with {:ok, data} <- ask_gpt(text, model),
         content <- OpenAIModel.get_content(data),
         {:ok, response} <- Jason.decode(content),
         cost <- OpenAIModel.get_cost(data, model) do
      {:ok, %{main_tag: response["main_tag"], other_tags: response["other_tags"], cost: cost}}
    else
      {:error, error} -> {:error, error}
    end
  end

  @spec ask_gpt(binary, OpenAIModel.t()) ::
          {:ok, map} | {:error, binary}
  defp ask_gpt(prompt, model) do
    OpenAI.chat_completion(
      model: model,
      response_format: %{type: "json_schema", json_schema: @json_schema},
      messages: [
        %{role: "system", content: "You are a helpful assistant."},
        %{role: "user", content: prompt0()},
        %{role: "assistant", content: @answer0},
        %{role: "user", content: prompt}
      ]
    )
  end

  @spec prompt0 :: binary
  defp prompt0 do
    """
    Classify a poll title and return a list of tags in json format

    "Should Spain invest in AI research and development?"
    """
  end
end
