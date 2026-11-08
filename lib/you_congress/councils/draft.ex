defmodule YouCongress.Councils.Draft do
  @moduledoc "Validates guest drafts and preserves them across authentication."
  alias YouCongress.{Councils, TrustRankings}

  def normalize(attrs) when is_map(attrs) do
    with lists when is_list(lists) and lists != [] <- Councils.value(attrs, :lists),
         true <- length(lists) <= 20,
         members <- Enum.flat_map(lists, &(Councils.value(&1, :members) || [])),
         true <- length(members) <= 200 do
      members =
        members
        |> Enum.map(fn m ->
          %{
            author_id: TrustRankings.parse_id(Councils.value(m, :author_id)),
            reason: Councils.value(m, :reason),
            source_url: Councils.value(m, :source_url)
          }
        end)
        |> Enum.uniq_by(& &1.author_id)

      if Enum.all?(members, &valid_member?/1) do
        {:ok,
         %{
           version: 1,
           lists: [%{id: nil, hall_id: nil, name: "Council", fallback: true, members: members}]
         }}
      else
        {:error, :invalid_draft}
      end
    else
      _ -> {:error, :invalid_draft}
    end
  rescue
    _ -> {:error, :invalid_draft}
  end

  def normalize(_), do: {:error, :invalid_draft}

  def apply(user, attrs) do
    with {:ok, draft} <- normalize(attrs), {:ok, council} <- Councils.ensure(user.author_id) do
      [list] = council.lists
      [draft_list] = draft.lists
      # Signing into an existing account must not silently discard its Council.
      members =
        Enum.uniq_by(
          draft_list.members ++ Enum.map(list.members, &Map.from_struct/1),
          & &1.author_id
        )

      members = Enum.reject(members, &(&1.author_id == user.author_id))

      Councils.save(user, %{
        version: council.version,
        lists: [%{draft_list | id: list.id, members: members}]
      })
    end
  end

  defp valid_member?(m) do
    is_integer(m.author_id) and
      (is_nil(m.reason) or (is_binary(m.reason) and String.length(m.reason) <= 5_000)) and
      (is_nil(m.source_url) or (is_binary(m.source_url) and String.length(m.source_url) <= 2_000))
  end
end
