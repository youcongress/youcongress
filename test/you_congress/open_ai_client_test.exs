defmodule YouCongress.OpenAIClientTest do
  use ExUnit.Case, async: false

  alias YouCongress.OpenAIClient

  setup {Req.Test, :verify_on_exit!}

  setup do
    saved_config = [
      {:you_congress, :openai, Application.fetch_env(:you_congress, :openai)},
      {:you_congress, :openai_req_options,
       Application.fetch_env(:you_congress, :openai_req_options)}
    ]

    Application.put_env(:you_congress, :openai,
      api_key: "test-api-key",
      organization_key: "test-organization",
      api_url: "https://api.openai.test"
    )

    Application.put_env(:you_congress, :openai_req_options, plug: {Req.Test, __MODULE__})

    on_exit(fn -> Enum.each(saved_config, &restore_config/1) end)
  end

  test "posts chat completion requests with authentication" do
    Req.Test.expect(__MODULE__, fn conn ->
      assert conn.method == "POST"
      assert conn.request_path == "/v1/chat/completions"
      assert Plug.Conn.get_req_header(conn, "authorization") == ["Bearer test-api-key"]
      assert Plug.Conn.get_req_header(conn, "openai-organization") == ["test-organization"]

      {:ok, body, conn} = Plug.Conn.read_body(conn)

      assert Jason.decode!(body) == %{
               "messages" => [%{"content" => "Hello", "role" => "user"}],
               "model" => "gpt-5-nano"
             }

      Req.Test.json(conn, %{"choices" => [%{"message" => %{"content" => "Hi"}}]})
    end)

    assert {:ok, %{"choices" => [_]}} =
             OpenAIClient.chat_completion(
               model: :"gpt-5-nano",
               messages: [%{role: "user", content: "Hello"}]
             )
  end

  test "posts embedding requests and returns decoded responses" do
    Req.Test.expect(__MODULE__, fn conn ->
      assert conn.request_path == "/v1/embeddings"
      Req.Test.json(conn, %{"data" => [%{"embedding" => [0.1, 0.2]}]})
    end)

    assert {:ok, %{"data" => [%{"embedding" => [0.1, 0.2]}]}} =
             OpenAIClient.embeddings(model: "text-embedding-3-small", input: "Hello")
  end

  test "returns an error without an API key" do
    Application.put_env(:you_congress, :openai, api_key: nil)

    assert OpenAIClient.embeddings(model: "text-embedding-3-small", input: "Hello") ==
             {:error, "Missing OPENAI_API_KEY"}
  end

  defp restore_config({app, key, {:ok, value}}), do: Application.put_env(app, key, value)
  defp restore_config({app, key, :error}), do: Application.delete_env(app, key)
end
