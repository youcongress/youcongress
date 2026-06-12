defmodule YouCongress.Halls.DescriptionGenerator do
  @moduledoc """
  Generates the short intro paragraph shown on a hall's topic-hub page.
  """

  alias YouCongress.DigitalTwins.OpenAIModel
  alias YouCongress.Tools.StringUtils

  @json_schema %{
    name: "hall_description",
    strict: true,
    schema: %{
      type: "object",
      properties: %{
        description: %{
          type: "string",
          description: "1-2 sentence intro for the topic page"
        }
      },
      required: ["description"],
      additionalProperties: false
    }
  }

  @spec generate(binary, OpenAIModel.t()) :: {:ok, binary} | {:error, any}
  def generate(hall_name, model \\ :"gpt-5-nano") do
    topic = StringUtils.titleize_hall(hall_name)

    prompt = """
    Write a neutral 1-2 sentence introduction (max 280 characters) to the topic
    "#{topic}" in the context of AI governance and policy. It will open a page of
    verified expert quotes for and against policy statements on this topic.

    Describe what the topic covers and the core point of debate among experts and
    policymakers. Never refer to "this page" or the quotes themselves; introduce
    the topic only. Be factual; no marketing language.
    Return JSON.
    """

    with {:ok, data} <- ask_gpt(prompt, model),
         content <- OpenAIModel.get_content(data),
         {:ok, %{"description" => description}} <- Jason.decode(content) do
      {:ok, description}
    else
      {:error, error} -> {:error, error}
      other -> {:error, other}
    end
  end

  defp ask_gpt(prompt, model) do
    OpenAI.chat_completion(
      model: model,
      response_format: %{type: "json_schema", json_schema: @json_schema},
      messages: [
        %{role: "system", content: "You are a helpful assistant."},
        %{role: "user", content: prompt}
      ]
    )
  end
end
