defmodule YouCongress.DigitalTwins.PublicFigures do
  @moduledoc """
  Generates a list of public figures who have publicly shared their views on a topic.
  """

  alias YouCongress.DigitalTwins.OpenAIModel

  @num_gen_opinions_in_prod 15
  @num_gen_opinions_in_dev 2
  @num_gen_opinions_in_test 2

  @spec generate_list(binary, OpenAIModel.t(), [binary]) ::
          {:ok, map} | {:error, binary}
  @spec generate_list(
          binary(),
          :"gpt-3.5-turbo-0125" | :"gpt-4" | :"gpt-4-1106-preview",
          boolean,
          list | nil
        ) ::
          {:error, binary()} | {:ok, %{cost: float(), names: any()}}
  def generate_list(topic, model, include_chatgpt_opinion, exclude_names \\ []) do
    num = num_gen_opinions()
    num = if include_chatgpt_opinion, do: num - 1, else: num
    question = get_question(topic, num, exclude_names)

    with {:ok, data} <- ask_gpt(question, model),
         content <- OpenAIModel.get_content(data),
         {:ok, decoded} <- Jason.decode(content),
         true <- decoded["names"] != nil,
         cost <- OpenAIModel.get_cost(data, model) do
      names = decoded["names"]
      names = if include_chatgpt_opinion, do: ["ChatGPT" | names], else: names
      {:ok, %{names: names, cost: cost}}
    else
      {:error, error} -> {:error, error}
    end
  end

  @spec get_question(binary, number, [binary]) :: binary
  defp get_question(topic, num_opinions, exclude_names) do
    exclude_names = Enum.join(exclude_names, ",")

    """
    User
    Tell me the name of #{num_opinions} public figures in json who have publicly shared their views on the topic "#{topic}".
    Example: { "names": ["Bill Gates, "Greta Thunberg"]}

    Exclude opinions from: #{exclude_names}
    """
  end

  @spec ask_gpt(binary, OpenAIModel.t()) ::
          {:ok, map} | {:error, binary}
  defp ask_gpt(question, model) do
    OpenAI.chat_completion(
      model: model,
      response_format: %{type: "json_object"},
      messages: [
        %{role: "system", content: "You are a helpful assistant."},
        %{role: "user", content: question}
      ]
    )
  end

  def num_gen_opinions do
    case Mix.env() do
      :test -> @num_gen_opinions_in_test
      :dev -> @num_gen_opinions_in_dev
      _ -> @num_gen_opinions_in_prod
    end
  end
end
