defmodule YouCongress.Opinions.AIReplier.AIComment do
  @moduledoc """
  Generate a reply from a digital twin via OpenAI's API.
  """

  alias YouCongress.DigitalTwins.OpenAIModel

  def generate_comment(ancestors_and_self, model) do
    {prompt, author} = get_prompt(ancestors_and_self)

    with {:ok, data} <- ask_gpt(prompt, model),
         content <- OpenAIModel.get_content(data),
         {:ok, opinion} <- Jason.decode(content) do
      {:ok, %{reply: opinion["reply"], author_id: author.id}}
    else
      {:error, error} -> {:error, error}
    end
  end

  defp get_prompt(ancestors_and_self) do
    {opinions, user_author, digital_twin_author} = print_opinions(ancestors_and_self)

    prompt =
      """
      #{opinions}

       Generate a reply in first person as if you were #{digital_twin_author.name} (#{digital_twin_author.bio}).
       The reply should be one or a few sentences long and be a plausible comment of #{digital_twin_author.name}.
       Also, make sure to answer the last question or comment from #{user_author.name || user_author.twitter_username}.
       Return a json object with the key reply:
       {
         "reply": "reply here"
       }
      """

    {prompt, digital_twin_author}
  end

  defp print_opinions(ancestors_and_self) do
    ancestors_and_self
    |> Enum.reverse()
    |> print_opinions("", nil, nil)
  end

  defp print_opinions([], output, last, second_to_last) do
    {output, last.author, second_to_last.author}
  end

  defp print_opinions([ancestor | rest], output, last, _second_to_last) do
    output =
      """
      #{output}
      #{ancestor.author.name || ancestor.author.username} (#{ancestor.author.bio}): #{ancestor.content}
      ----
      """

    print_opinions(rest, output, ancestor, last)
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
