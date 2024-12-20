defmodule YouCongress.Votings.GeneratorAI do
  @moduledoc """
  Generate a voting
  """

  alias YouCongress.DigitalTwins.OpenAIModel

  @spec generate(OpenAIModel.t()) :: {:ok, map} | {:error, binary}
  def generate(model \\ :"gpt-4o") do
    text = """
    Existent polls:
    #{YouCongress.Votings.list_votings(hall_name: "ai") |> Enum.map(& &1.title) |> Enum.join("\n")}

    Return a new yes/no question for a new poll in json format (different from the existent ones above) related to one or more of these:
    - Public interest AI
    - Future of work
    - AI Innovation and culture
    - Trust in AI Global
    - Global AI governance

    Output example in JSON:

    {
      "poll": "Should third-party audits be mandatory for major AI systems?"
    }
    """

    classify_gpt(text, model)
  end

  @spec classify_gpt(binary, OpenAIModel.t()) :: {:ok, map} | {:error, binary}
  defp classify_gpt(text, model) do
    with {:ok, data} <- ask_gpt(text, model),
         content <- OpenAIModel.get_content(data),
         {:ok, %{"poll" => voting_title}} <- Jason.decode(content),
         cost <- OpenAIModel.get_cost(data, model) do
      {:ok, %{voting_title: voting_title, cost: cost}}
    else
      {:error, error} -> {:error, error}
    end
  end

  @spec ask_gpt(binary, OpenAIModel.t()) ::
          {:ok, map} | {:error, binary}
  defp ask_gpt(prompt, model) do
    OpenAI.chat_completion(
      model: model,
      response_format: %{type: "json_object"},
      messages: [
        %{role: "system", content: "You are a helpful assistant."},
        %{role: "user", content: prompt}
      ]
    )
  end
end
