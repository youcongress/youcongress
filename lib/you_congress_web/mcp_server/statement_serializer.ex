defmodule YouCongressWeb.MCPServer.StatementSerializer do
  @moduledoc false

  alias Ecto.Association.NotLoaded

  @spec halls(struct() | map()) :: [map()]
  def halls(%{halls: %NotLoaded{}}), do: []

  def halls(%{halls: halls}) when is_list(halls) do
    halls
    |> Enum.sort_by(& &1.name)
    |> Enum.map(fn hall ->
      %{
        id: hall.id,
        name: hall.name
      }
    end)
  end

  def halls(_), do: []
end
