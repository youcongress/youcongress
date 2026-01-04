defmodule YouCongress.DigitalTwins.OpenAIModel do
  @moduledoc """
  Provides the cost of using OpenAI models.
  """

  @type t :: :"gpt-4o" | :"gpt-4o-mini" | :"gpt-5" | :"gpt-5-mini" | :"gpt-5-nano"

  # @token_cost %{
  #   :"gpt-4o" => %{completion_tokens: 0.02, prompt_tokens: 0.005},
  #   :"gpt-4o-mini" => %{completion_tokens: 0.0024, prompt_tokens: 0.0006},
  #   :"gpt-5" => %{completion_tokens: 0.01, prompt_tokens: 0.00125, cached_input_tokens: 0.000125},
  #   :"gpt-5-mini" => %{
  #     completion_tokens: 0.002,
  #     prompt_tokens: 0.00025,
  #     cached_input_tokens: 0.000025
  #   },
  #   :"gpt-5-nano" => %{
  #     completion_tokens: 0.0004,
  #     prompt_tokens: 0.00005,
  #     cached_input_tokens: 0.000005
  #   }
  # }

  @spec get_content(map) :: binary | {:error, binary}
  def get_content(%{choices: choices}) when is_list(choices) and choices != [] do
    hd(choices)["message"]["content"]
  end

  def get_content(%{"choices" => choices}) when is_list(choices) and choices != [] do
    hd(choices)["message"]["content"]
  end

  def get_content(%{choices: nil}), do: {:error, "No choices returned from OpenAI"}
  def get_content(%{"choices" => nil}), do: {:error, "No choices returned from OpenAI"}
  def get_content(%{choices: []}), do: {:error, "Empty choices array returned from OpenAI"}
  def get_content(%{"choices" => []}), do: {:error, "Empty choices array returned from OpenAI"}
  def get_content(_), do: {:error, "Invalid response format from OpenAI"}

  @spec get_cost(map, __MODULE__.t()) :: number
  def get_cost(_data, _model) do
    # usage = Map.get(data, "usage")
    # completion =
    #   usage["completion_tokens"] * @token_cost[model][:completion_tokens] / 1000

    # prompt = usage["prompt_tokens"] * @token_cost[model][:prompt_tokens] / 1000
    # cached_input_tokens = data["usage"]["cached_input_tokens"] || 0

    # cached_input_tokens =
    #   cached_input_tokens * (@token_cost[model][:cached_input_tokens] || 0) / 1000

    # completion + prompt + cached_input_tokens
    0.0
  end
end
