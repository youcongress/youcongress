defmodule YouCongress.Opinions.AIComment do
  @moduledoc """
  Generate a reply from a digital twin via OpenAI's API.
  """

  alias YouCongress.DigitalTwins.OpenAIModel

  def generate_comment(voting_title, ancestors_and_self, model) do
    {prompt, author} = get_prompt(voting_title, ancestors_and_self)
    IO.inspect(prompt)
    IO.inspect(author)

    with {:ok, data} <- ask_gpt(prompt, model),
         content <- OpenAIModel.get_content(data),
         {:ok, opinion} <- Jason.decode(content) do
      {:ok, %{reply: opinion["reply"], author_id: author.id}}
    else
      {:error, error} -> {:error, error}
    end
  end

  defp get_prompt(voting_title, ancestors_and_self) do
    {opinions, author} = print_opinions(ancestors_and_self)

    prompt =
      """
      Poll: #{voting_title}

      #{opinions}

       Generate a reply in first person as if you were #{author.name} (#{author.bio}).
       The reply should be one or a few sentences long.
       Return a json object with the key reply:
       {
         "reply": "reply here"
       }
      """

    {prompt, author}
  end

  defp print_opinions(ancestors_and_self) do
    ancestors_and_self
    |> Enum.reverse()
    |> print_opinions("", nil, nil)
  end

  defp print_opinions([], output, _last, second_to_last) do
    {output, second_to_last.author}
  end

  defp print_opinions([ancestor | rest], output, last, _second_to_last) do
    output =
      """
      #{output}
      #{ancestor.author.name} (#{ancestor.author.bio}): #{ancestor.content}
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
