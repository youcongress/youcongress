defmodule YouCongress.DigitalTwins.OpenAIModel do
  @type t :: :"gpt-3.5-turbo-0125" | :"gpt-4" | :"gpt-4-1106-preview"

  @token_cost %{
    :"gpt-4-1106-preview" => %{completion_tokens: 0.03, prompt_tokens: 0.01},
    :"gpt-4" => %{completion_tokens: 0.06, prompt_tokens: 0.03},
    :"gpt-3.5-turbo-0125" => %{completion_tokens: 0.002, prompt_tokens: 0.0015}
  }

  @spec get_cost(map, __MODULE__.t()) :: number
  def get_cost(data, model) do
    completion = data.usage["completion_tokens"] * @token_cost[model][:completion_tokens] / 1000
    prompt = data.usage["prompt_tokens"] * @token_cost[model][:prompt_tokens] / 1000
    completion + prompt
  end
end
