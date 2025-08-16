defmodule YouCongress.DigitalTwins.OpenAIModel do
  @moduledoc """
  Provides the cost of using OpenAI models.
  """

  @type t :: :"gpt-3.5-turbo-0125" | :"gpt-4" | :"gpt-4-turbo-2024-04-09" | :"gpt-4o"

  @token_cost %{
    :"gpt-4o" => %{completion_tokens: 0.02, prompt_tokens: 0.005},
    :"gpt-4o-mini" => %{completion_tokens: 0.0024, prompt_tokens: 0.0006},
    :"gpt-5" => %{completion_tokens: 0.01, prompt_tokens: 0.00125}
  }

  @spec get_content(map) :: [binary]
  def get_content(data) do
    hd(data.choices)["message"]["content"]
    |> String.split("\n\n")
  end

  @spec get_cost(map, __MODULE__.t()) :: number
  def get_cost(data, model) do
    completion = data.usage["completion_tokens"] * @token_cost[model][:completion_tokens] / 1000
    prompt = data.usage["prompt_tokens"] * @token_cost[model][:prompt_tokens] / 1000
    completion + prompt
  end
end
