defmodule YouCongress.WikipediaUrl do
  @moduledoc """
  Parses canonical HTTPS article URLs on trusted Wikipedia hosts.

  Keeping this validation in one place ensures stored URLs and outbound
  MediaWiki requests use the same trust boundary.
  """

  @wikipedia_host ~r/\A[a-z0-9](?:[a-z0-9-]{0,61}[a-z0-9])?\.wikipedia\.org\z/

  @spec parse(term()) :: {:ok, %{host: String.t(), title: String.t()}} | {:error, :invalid_url}
  def parse(url) when is_binary(url) do
    uri = URI.parse(url)
    host = uri.host && String.downcase(uri.host)

    with "https" <- uri.scheme,
         host when is_binary(host) <- host,
         true <- Regex.match?(@wikipedia_host, host),
         nil <- uri.userinfo,
         port when port in [nil, 443] <- uri.port,
         nil <- uri.query,
         nil <- uri.fragment,
         "/wiki/" <> encoded_title when encoded_title != "" <- uri.path || "",
         true <- valid_encoded_title?(encoded_title),
         title when title != "" <- URI.decode(encoded_title),
         true <- String.valid?(title),
         false <- Regex.match?(~r/[\x00-\x1F\x7F]/u, title) do
      {:ok, %{host: host, title: title}}
    else
      _ -> {:error, :invalid_url}
    end
  rescue
    _ -> {:error, :invalid_url}
  end

  def parse(_), do: {:error, :invalid_url}

  @spec valid?(term()) :: boolean()
  def valid?(url), do: match?({:ok, _}, parse(url))

  defp valid_encoded_title?(title) do
    not Regex.match?(~r/%(?![0-9A-Fa-f]{2})/, title)
  end
end
