defmodule YouCongress.DigitalTwins.OpenAIModel do
  @moduledoc """
  Provides the cost of using OpenAI models.
  """

  @type t :: :"gpt-4o" | :"gpt-4o-mini" | :"gpt-5" | :"gpt-5-mini" | :"gpt-5-nano"

  @token_cost %{
    :"gpt-4o" => %{completion_tokens: 0.02, prompt_tokens: 0.005},
    :"gpt-4o-mini" => %{completion_tokens: 0.0024, prompt_tokens: 0.0006},
    :"gpt-5" => %{completion_tokens: 0.01, prompt_tokens: 0.00125, cached_input_tokens: 0.000125},
    :"gpt-5-mini" => %{completion_tokens: 0.002, prompt_tokens: 0.00025, cached_input_tokens: 0.000025},
    :"gpt-5-nano" => %{completion_tokens: 0.0004, prompt_tokens: 0.00005, cached_input_tokens: 0.000005}
  }

  @spec get_content(map) :: binary
  def get_content(data) do
    hd(data["choices"])["message"]["content"]
  end

  @spec get_cost(map, __MODULE__.t()) :: number
  def get_cost(data, model) do
    IO.inspect(data["usage"], label: "----------------- data[usage]")
    completion = data["usage"]["completion_tokens"] * @token_cost[model][:completion_tokens] / 1000
    prompt = data["usage"]["prompt_tokens"] * @token_cost[model][:prompt_tokens] / 1000
    cached_input_tokens = data["usage"]["cached_input_tokens"] || 0
    cached_input_tokens = cached_input_tokens * (@token_cost[model][:cached_input_tokens] || 0) / 1000
    completion + prompt + cached_input_tokens
  end
end
