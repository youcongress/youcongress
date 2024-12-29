defmodule YouCongress.FactChecker do
  @moduledoc """
  The FactChecker context.
  """

  require Logger

  alias YouCongress.DigitalTwins.OpenAIModel

  def classify_text(text) do
    prompt = """
    Return a json splitting it into chunks of text and indicating if each of them is a "fact", "false", "opinion", "unknown".
    If you're not sure it is a fact, classify it as "unknown".
    Include the same spaces and newlines as unknown chunks.

    Example input:
    "The Earth is not flat. But it is beautiful."

    Example output:
    {
      "content": [
        {"text": "The Earth is not flat.", "classification": "fact"},
        {"text": " ", "classification": "unknown"},
        {"text": "But it is beautiful", "classification": "opinion"}
      ]
    }

    Example 2:
    "The Earth completes one rotation around its axis in approximately 24 hours, which gives us our day and night cycle.

    Many people believe that drinking hot water with lemon in the morning boosts metabolism and aids weight loss.
    Unicorns were commonly kept as pets by medieval European nobility until the 16th century.

    Studies have shown that listening to classical music while studying can improve concentration and memory retention."

    Example output:
    {
      "content": [
        {"text": "The Earth completes one rotation around its axis in approximately 24 hours, which gives us our day and night cycle.", "classification": "fact"},
        {"text": "\n\n", "classification": "unknown"},
        {"text": "Many people believe that drinking hot water with lemon in the morning boosts metabolism and aids weight loss.", "classification": "opinion"},
        {"text": "\n", "classification": "unknown"},
        {"text": "Unicorns were commonly kept as pets by medieval European nobility until the 16th century.", "classification": "false"},
        {"text": "\n\n", "classification": "unknown"},
        {"text": "Studies have shown that listening to classical music while studying can improve concentration and memory retention.", "classification": "fact"}
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
      error ->
        Logger.error("Error classifying text: #{inspect(error)}")
        {:error, error}
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
