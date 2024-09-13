defmodule YouCongress.DigitalTwins.PublicFigures do
  @moduledoc """
  Generates a list of public figures who have publicly shared their views on a topic.
  """

  alias YouCongress.DigitalTwins.OpenAIModel

  @num_gen_opinions_in_prod 15
  @num_gen_opinions_in_dev 2
  @num_gen_opinions_in_test 2

  @spec generate_list(binary, OpenAIModel.t(), list | nil) ::
          {:error, binary} | {:ok, %{cost: float, votes: list}}
  def generate_list(topic, model, exclude_names \\ []) do
    prompt = get_prompt(topic, num_gen_opinions(), exclude_names)

    with {:ok, data} <- ask_gpt(prompt, model),
         content <- OpenAIModel.get_content(data),
         {:ok, decoded} <- Jason.decode(content),
         cost <- OpenAIModel.get_cost(data, model) do
      {:ok, %{votes: decoded["votes"], cost: cost}}
    else
      {:error, error} -> {:error, error}
    end
  end

  @spec get_prompt(binary, number, [binary]) :: binary
  defp get_prompt(topic, num_opinions, exclude_names) do
    exclude_names = Enum.join(exclude_names, ",")

    """
    Topic: Climate Change

    Tell me the name of 2 public figures or experts in json who have publicly shared their views on the topic "#{topic}".
    Also, rate how much they agree from: "Strongly agree", "Agree", "Abstain", "Disagree", "Strongly disagree".

    Example: { "votes": [["Bill Gates", "Strongly agree"], ["Greta Thunberg", "Disagree"]]}

    Topic: Is Elixir better than Ruby for web development?

    Tell me the name of 2 public figures or experts in json who have publicly shared their views on the topic "#{topic}".
    Also, rate how much they agree from: "Strongly agree", "Agree", "Abstain", "Disagree", "Strongly disagree".

    Example: { "votes": [["José Valim", "Strongly agree"], ["David Heinemeier Hansson", "Strongly Disagree"]]}

    Topic: #{topic}

    Tell me the name of #{num_opinions} public figures or experts in json who have publicly shared their views on the topic "#{topic}".
    Also, rate how much they agree from: "Strongly agree", "Agree", "Abstain", "Disagree", "Strongly disagree".
    Try to include diverse votes (e.g. not only "Strongly agree"), unless all public figures agree.
    It should be plausible that the public figure has that opinion about the topic (E.g. an actor probably won't have an opinion on programming languages, but well-known programmers might).

    Exclude these public figures: #{exclude_names}
    """
  end

  @spec ask_gpt(binary, OpenAIModel.t()) :: {:ok, map} | {:error, binary}
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

  def num_gen_opinions do
    case Application.get_env(:you_congress, :env) do
      :test -> @num_gen_opinions_in_test
      :dev -> @num_gen_opinions_in_dev
      _ -> @num_gen_opinions_in_prod
    end
  end
end
