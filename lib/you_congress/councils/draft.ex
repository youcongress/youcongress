defmodule YouCongress.Councils.Draft do
  @moduledoc "Validates untrusted, portable guest drafts before registration."
  alias YouCongress.{Councils, TrustRankings}

  def normalize(attrs) when is_map(attrs) do
    lists = Councils.value(attrs, :lists)

    if is_list(lists) && lists != [] && Enum.all?(lists, &is_map/1) do
      normalized =
        Enum.with_index(lists)
        |> Enum.map(fn {l, i} ->
          %{
            id: nil,
            hall_id: TrustRankings.parse_id(Councils.value(l, :hall_id)),
            name: Councils.value(l, :name) || "General",
            fallback: i == length(lists) - 1,
            members:
              Enum.map(Councils.value(l, :members) || [], fn m ->
                %{
                  author_id: TrustRankings.parse_id(Councils.value(m, :author_id)),
                  reason: Councils.value(m, :reason),
                  source_url: Councils.value(m, :source_url)
                }
              end)
          }
        end)

      if is_nil(List.last(normalized).hall_id),
        do: {:ok, %{version: 1, lists: normalized}},
        else: {:error, :invalid_draft}
    else
      {:error, :invalid_draft}
    end
  rescue
    _ -> {:error, :invalid_draft}
  end

  def normalize(_), do: {:error, :invalid_draft}

  def apply(user, attrs) do
    with {:ok, draft} <- normalize(attrs), {:ok, council} <- Councils.ensure(user.author_id) do
      fallback = Enum.find(council.lists, & &1.fallback)
      lists = List.update_at(draft.lists, -1, &%{&1 | id: fallback.id})
      Councils.save(user, %{version: council.version, lists: lists})
    end
  end
end
