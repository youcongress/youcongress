defmodule YouCongressWeb.MCPServer.TrustNetwork do
  @moduledoc "Read public councils, rankings, recommendations, and participating communities."
  use Anubis.Server.Component, type: :tool
  alias Anubis.Server.Response

  schema do
    field :view, :string, required: true
    field :author_id, :integer
    field :scope, :string
    field :community, :integer
    field :nominators, :string
    field :nominees, :string
  end

  @impl true
  def execute(params, frame) do
    data =
      case params.view do
        "rankings" ->
          YouCongress.TrustRankings.ranking(params[:scope] || "general", %{
            "community" => params[:community],
            "nominators" => params[:nominators],
            "nominees" => params[:nominees]
          })

        "communities" ->
          Enum.map(
            YouCongress.TrustNetwork.communities(),
            &Map.take(&1, [:id, :name, :description])
          )

        "council" ->
          public_council(params[:author_id])

        "recommendations" ->
          if params[:author_id],
            do:
              Enum.map(YouCongress.TrustNetwork.recommendations(params.author_id), fn row ->
                Map.take(row.record, [:nominee_id, :scope, :reason, :source_url])
                |> Map.put(:name, row.name)
              end),
            else: %{error: "author_id required"}

        _ ->
          %{error: "Choose rankings, communities, council, or recommendations"}
      end

    {:reply, Response.json(Response.tool(), data), frame}
  end

  defp public_council(nil), do: %{error: "author_id required"}

  defp public_council(id) do
    case YouCongress.Councils.public(id) do
      nil -> %{error: "Council is not public"}
      council -> YouCongress.Councils.editable(council)
    end
  end
end
