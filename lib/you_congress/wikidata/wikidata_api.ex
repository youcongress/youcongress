defmodule YouCongress.Wikidata.WikidataApi do
  @moduledoc """
  Resolves the Wikidata entity id (e.g. "Q42") for a Wikipedia page.

  It queries the MediaWiki API of the same Wikipedia (any language) the URL
  points to, asking for the `wikibase_item` page property.
  """

  require Logger

  @behaviour YouCongress.Wikidata

  @receive_timeout 30_000

  @doc """
  Returns the Wikidata id for a given Wikipedia URL.

  ## Examples

      iex> get_wikidata_id("https://en.wikipedia.org/wiki/Douglas_Adams")
      {:ok, "Q42"}

      iex> get_wikidata_id("https://en.wikipedia.org/wiki/Nonexistent_Page_123")
      {:ok, nil}

  """
  @impl YouCongress.Wikidata
  @spec get_wikidata_id(String.t()) ::
          {:ok, String.t() | nil} | {:error, term()}
  def get_wikidata_id(wikipedia_url) when is_binary(wikipedia_url) do
    with {:ok, host, title} <- parse_url(wikipedia_url),
         {:ok, body} <- fetch(host, title) do
      {:ok, extract_wikibase_item(body)}
    end
  end

  def get_wikidata_id(_), do: {:error, :invalid_url}

  @doc """
  Returns the X (Twitter) username (P2002) and numeric user id (P6552) for a
  Wikidata entity id.

  ## Examples

      iex> get_twitter("Q42")
      {:ok, %{username: "...", id_str: "..."}}

  """
  @impl YouCongress.Wikidata
  @spec get_twitter(String.t()) :: {:ok, YouCongress.Wikidata.twitter()} | {:error, term()}
  def get_twitter(wikidata_id) when is_binary(wikidata_id) and wikidata_id != "" do
    case fetch_entity(wikidata_id) do
      {:ok, body} ->
        {:ok,
         %{
           username: extract_claim(body, wikidata_id, "P2002"),
           id_str: extract_claim(body, wikidata_id, "P6552")
         }}

      {:error, reason} ->
        {:error, reason}
    end
  end

  def get_twitter(_), do: {:error, :invalid_wikidata_id}

  defp fetch_entity(wikidata_id) do
    url = "https://www.wikidata.org/wiki/Special:EntityData/#{wikidata_id}.json"

    case Req.get(url, receive_timeout: @receive_timeout) do
      {:ok, %Req.Response{status: status, body: body}} when status in 200..299 ->
        {:ok, body}

      {:ok, %Req.Response{status: status}} ->
        Logger.error("Wikidata entity call failed: status=#{status} url=#{url}")
        {:error, {:http_error, status}}

      {:error, reason} ->
        Logger.error("Wikidata entity request failed: #{inspect(reason)}")
        {:error, reason}
    end
  end

  defp extract_claim(%{"entities" => entities}, wikidata_id, property) do
    entities
    |> get_in([wikidata_id, "claims", property])
    |> case do
      [statement | _] ->
        get_in(statement, ["mainsnak", "datavalue", "value"])

      _ ->
        nil
    end
  end

  defp extract_claim(_, _, _), do: nil

  defp parse_url(wikipedia_url) do
    uri = URI.parse(wikipedia_url)

    with host when is_binary(host) <- uri.host,
         "/wiki/" <> encoded_title <- uri.path || "",
         title when title != "" <- URI.decode(encoded_title) do
      {:ok, host, title}
    else
      _ -> {:error, :invalid_url}
    end
  end

  defp fetch(host, title) do
    url = "https://#{host}/w/api.php"

    params = [
      action: "query",
      prop: "pageprops",
      ppprop: "wikibase_item",
      redirects: 1,
      format: "json",
      titles: title
    ]

    case Req.get(url, params: params, receive_timeout: @receive_timeout) do
      {:ok, %Req.Response{status: status, body: body}} when status in 200..299 ->
        {:ok, body}

      {:ok, %Req.Response{status: status}} ->
        Logger.error("Wikidata API call failed: status=#{status} url=#{url} title=#{title}")
        {:error, {:http_error, status}}

      {:error, reason} ->
        Logger.error("Wikidata API request failed: #{inspect(reason)}")
        {:error, reason}
    end
  end

  defp extract_wikibase_item(%{"query" => %{"pages" => pages}}) when is_map(pages) do
    pages
    |> Map.values()
    |> Enum.find_value(fn page ->
      get_in(page, ["pageprops", "wikibase_item"])
    end)
  end

  defp extract_wikibase_item(_), do: nil
end
