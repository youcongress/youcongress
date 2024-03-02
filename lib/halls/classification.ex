defmodule YouCongress.Halls.Classification do
  @moduledoc """
  Generate the tags (halls) for a voting
  """

  alias YouCongress.DigitalTwins.OpenAIModel

  @model :"gpt-3.5-turbo-0125"

  @answer0 """
  {
    "tags": ["ai", "spain"]
  }
  """

  @spec classify(binary, atom) :: {:ok, map} | {:error, binary}
  def classify(text, model \\ @model) do
    if Mix.env() == :test do
      {:ok, %{tags: ["ai", "spain"]}}
    else
      case classify_gpt(text, model) do
        {:ok, %{tags: tags, cost: cost}} -> {:ok, %{tags: tags, cost: cost}}
        {:error, error} -> {:error, error}
      end
    end
  end

  defp classify_gpt(text, model) do
    with {:ok, data} <- ask_gpt(text, model),
         content <- OpenAIModel.get_content(data),
         {:ok, response} <- Jason.decode(content),
         cost <- OpenAIModel.get_cost(data, model) do
      {:ok, %{tags: response["tags"], cost: cost}}
    else
      {:error, error} -> {:error, error}
    end
  end

  @spec ask_gpt(binary, atom) ::
          {:ok, map} | {:error, binary}
  defp ask_gpt(question, model) do
    OpenAI.chat_completion(
      model: model,
      response_format: %{type: "json_object"},
      messages: [
        %{role: "system", content: "You are a helpful assistant."},
        %{role: "user", content: question0()},
        %{role: "assistant", content: @answer0},
        %{role: "user", content: question}
      ]
    )
  end

  defp question0 do
    """
    Classify a text and return a list of tags:

    #{YouCongress.Halls.Hall.names_str()}

    Include a list of tags in json for "Should Spain invest in AI research and development?"
    """
  end
end
