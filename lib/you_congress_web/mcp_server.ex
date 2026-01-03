defmodule YouCongress.MCPServer do
  use Anubis.Server,
    name: "My Server",
    version: "1.0.0",
    capabilities: [:tools]

  @impl true
  # this callback will be called when the
  # MCP initialize lifecycle completes
  def init(_client_info, frame) do
    {:ok,
     frame
     |> assign(counter: 0)
     |> register_tool("echo",
       input_schema: %{
         text: {:required, :string, max: 150, description: "the text to be echoed"}
       },
       annotations: %{read_only: true},
       description: "echoes everything the user says to the LLM"
     )}
  end

  @impl true
  def handle_tool("echo", %{text: text}, frame) do
    Logger.info("This tool was called #{frame.assigns.counter + 1}")
    {:reply, text, assign(frame, counter: frame.assigns.counter + 1)}
  end
end
