defmodule YouCongress.Opinions.ContentEmbedding do
  @moduledoc """
  Decides when to generate, keep, or clear the `:content_embedding` of an
  opinion based on its attrs.

  Only sourced quotes (content present plus a source_url or source_text) carry a
  content embedding. The embedding is (re)generated when the quote is new, just
  became sourced, or its content changed; it is cleared when the opinion stops
  being a sourced quote.
  """

  alias YouCongress.Embeddings
  alias YouCongress.Opinions.Opinion

  @doc """
  Returns `attrs` with `:content_embedding` set, cleared, or untouched depending
  on whether the resulting opinion should be an embedded sourced quote.
  """
  def put(attrs, %Opinion{} = opinion) when is_map(attrs) do
    if has_attr?(attrs, :content_embedding) do
      attrs
    else
      content = effective_attr(attrs, :content, opinion.content)
      source_url = effective_attr(attrs, :source_url, opinion.source_url)
      source_text = effective_attr(attrs, :source_text, opinion.source_text)

      cond do
        not sourced_quote?(content, source_url, source_text) ->
          maybe_clear_content_embedding(attrs, opinion)

        should_generate_content_embedding?(attrs, opinion, content, source_url, source_text) ->
          case Embeddings.embed(content) do
            {:ok, embedding} when is_list(embedding) ->
              put_attr(attrs, :content_embedding, embedding)

            _ ->
              maybe_clear_stale_content_embedding(attrs, opinion)
          end

        true ->
          attrs
      end
    end
  end

  def put(attrs, _opinion), do: attrs

  defp should_generate_content_embedding?(attrs, opinion, content, source_url, source_text) do
    sourced_quote?(content, source_url, source_text) and
      (is_nil(opinion.id) or is_nil(opinion.content_embedding) or
         content_changed?(attrs, opinion) or quote_became_sourced?(attrs, opinion))
  end

  defp sourced_quote?(content, source_url, source_text),
    do: present?(content) and (present?(source_url) or present?(source_text))

  defp maybe_clear_content_embedding(attrs, %Opinion{content_embedding: nil}), do: attrs

  defp maybe_clear_content_embedding(attrs, %Opinion{}),
    do: put_attr(attrs, :content_embedding, nil)

  defp maybe_clear_stale_content_embedding(attrs, opinion) do
    if content_changed?(attrs, opinion) or quote_became_sourced?(attrs, opinion) do
      maybe_clear_content_embedding(attrs, opinion)
    else
      attrs
    end
  end

  defp content_changed?(attrs, opinion) do
    has_attr?(attrs, :content) and get_attr(attrs, :content) != opinion.content
  end

  defp quote_became_sourced?(attrs, opinion) do
    (has_attr?(attrs, :source_url) or has_attr?(attrs, :source_text)) and
      not (present?(opinion.source_url) or present?(opinion.source_text))
  end

  defp has_attr?(attrs, key) do
    Map.has_key?(attrs, key) or Map.has_key?(attrs, Atom.to_string(key))
  end

  defp get_attr(attrs, key) do
    string_key = Atom.to_string(key)

    cond do
      Map.has_key?(attrs, key) -> Map.get(attrs, key)
      Map.has_key?(attrs, string_key) -> Map.get(attrs, string_key)
      true -> nil
    end
  end

  defp effective_attr(attrs, key, fallback) do
    if has_attr?(attrs, key), do: get_attr(attrs, key), else: fallback
  end

  defp put_attr(attrs, key, value), do: Map.put(attrs, attr_key(attrs, key), value)

  defp attr_key(attrs, key) do
    string_key = Atom.to_string(key)
    keys = Map.keys(attrs)

    cond do
      Map.has_key?(attrs, string_key) -> string_key
      Enum.any?(keys, &is_binary/1) and not Enum.any?(keys, &is_atom/1) -> string_key
      true -> key
    end
  end

  defp present?(value) when is_binary(value), do: String.trim(value) != ""
  defp present?(value), do: not is_nil(value)
end
