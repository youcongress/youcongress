defmodule YouCongress.OpenAIClient do
  @moduledoc """
  Minimal OpenAI API client for the chat-completions and embeddings endpoints.

  Keeping these calls on Req avoids the legacy HTTPoison/Hackney dependency
  while preserving the response shape expected by the application.
  """

  @default_api_url "https://api.openai.com"
  @default_receive_timeout 60_000

  def chat_completion(params), do: post("/v1/chat/completions", params)
  def embeddings(params), do: post("/v1/embeddings", params)

  defp post(path, params) do
    case config(:api_key) do
      api_key when is_binary(api_key) and api_key != "" ->
        request(path, params, api_key)

      _ ->
        {:error, "Missing OPENAI_API_KEY"}
    end
  end

  defp request(path, params, api_key) do
    options =
      [
        url: api_url() <> path,
        json: Map.new(params),
        headers: request_headers(api_key),
        receive_timeout: receive_timeout(),
        retry: false
      ] ++ Application.get_env(:you_congress, :openai_req_options, [])

    case Req.post(options) do
      {:ok, %Req.Response{status: status, body: body}} when status in 200..299 ->
        {:ok, body}

      {:ok, %Req.Response{status: status, body: body}} ->
        {:error, %{status_code: status, body: body}}

      {:error, reason} ->
        {:error, reason}
    end
  end

  defp api_url do
    :api_url
    |> config(@default_api_url)
    |> String.trim_trailing("/")
  end

  defp request_headers(api_key) do
    headers = [{"authorization", "Bearer " <> api_key}]

    case config(:organization_key) do
      organization_key when is_binary(organization_key) and organization_key != "" ->
        [{"openai-organization", organization_key} | headers]

      _ ->
        headers
    end
  end

  defp receive_timeout do
    :http_options
    |> config([])
    |> Keyword.get(:recv_timeout, @default_receive_timeout)
  end

  defp config(key, default \\ nil) do
    :you_congress
    |> Application.get_env(:openai, [])
    |> Keyword.get(key, default)
  end
end
