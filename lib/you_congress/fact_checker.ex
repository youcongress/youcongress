defmodule YouCongress.FactChecker do
  @moduledoc """
  The FactChecker context.
  """

  alias YouCongress.DigitalTwins.OpenAIModel

  def classify_text(text) do
    prompt = """
    Return a json splitting it into chunks of text and indicating if each of them is a "fact", "false", "opinion", "unknown".
    If you're not sure it is a fact, classify it as "unknown".

    Example input:
    "The Earth is not flat. But it is beautiful."

    Example output:
    {
      "content": [
        {"text": "The Earth is not flat.", "classification": "fact"},
        {"text": "But it is beautiful", "classification": "opinion"}
      ]
    }

    Example 2:
    "Obama was the first president of the US. He was awarded the Nobel peace prize."

    Example output:
    {
      "content": [
        {"text": "Obama was the first president of the US.", "classification": "false"},
        {"text": "He was awarded the Nobel peace prize.", "classification": "opinion"}
      ]
    }

    Input:
    #{text}
    """

    with {:ok, data} <- ask_gpt(prompt, :"gpt-4o"),
         content <- OpenAIModel.get_content(data),
         {:ok, %{"content" => analyzed}} <- Jason.decode(content) do
      {:ok, analyzed}
    else
      error -> {:error, error}
    end
  end

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
