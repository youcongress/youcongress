defmodule YouCongress.Halls.Classification do
  @moduledoc """
  Generate the tags (halls) for a voting
  """

  @type model_type :: :"gpt-3.5-turbo-0125" | :"gpt-4" | :"gpt-4-1106-preview"

  @model :"gpt-3.5-turbo-0125"
  @models [:"gpt-4-1106-preview", :"gpt-4", :"gpt-3.5-turbo-0125"]
  @token_cost %{
    :"gpt-4-1106-preview" => %{completion_tokens: 0.03, prompt_tokens: 0.01},
    :"gpt-4" => %{completion_tokens: 0.06, prompt_tokens: 0.03},
    :"gpt-3.5-turbo-0125" => %{completion_tokens: 0.002, prompt_tokens: 0.0015}
  }

  @answer0 """
  {
    "tags": ["ai", "spain"]
  }
  """

  @spec classify(binary, model_type) :: {:ok, map} | {:error, binary}
  def classify(text, model \\ @model) when model in @models do
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
         content <- get_content(data),
         {:ok, response} <- Jason.decode(content),
         cost <- get_cost(data, model) do
      {:ok, %{tags: response["tags"], cost: cost}}
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
        %{role: "user", content: question0()},
        %{role: "assistant", content: @answer0},
        %{role: "user", content: question}
      ]
    )
  end

  defp question0() do
    """
    Classify a text and return a list of tags:

    #{YouCongress.Halls.Hall.names_str()}

    Include a list of tags in json for "Should Spain invest in AI research and development?"
    """
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
