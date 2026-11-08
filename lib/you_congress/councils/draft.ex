defmodule YouCongress.Councils.Draft do
  @moduledoc "Validates topic drafts and preserves them across authentication."
  alias YouCongress.{Councils, TrustRankings}

  def normalize(attrs) when is_map(attrs) do
    with lists when is_list(lists) and lists != [] <- Councils.value(attrs, :lists),
         true <- length(lists) <= 20 do
      lists =
        Enum.with_index(lists)
        |> Enum.map(fn {list, index} ->
          members =
            Enum.map(Councils.value(list, :members) || [], fn m ->
              %{
                author_id: TrustRankings.parse_id(Councils.value(m, :author_id)),
                reason: Councils.value(m, :reason),
                source_url: Councils.value(m, :source_url)
              }
            end)
            |> Enum.uniq_by(& &1.author_id)

          %{
            id: nil,
            name: Councils.value(list, :name) || "General",
            hall_id: TrustRankings.parse_id(Councils.value(list, :hall_id)),
            fallback: index == length(lists) - 1,
            members: members
          }
        end)

      valid =
        Enum.all?(lists, fn l ->
          is_binary(l.name) && String.length(l.name) in 1..120 &&
            Enum.all?(l.members, &valid_member?/1)
        end)

      if valid && is_nil(List.last(lists).hall_id) &&
           Enum.sum(Enum.map(lists, &length(&1.members))) <= 200,
         do: {:ok, %{version: 1, lists: lists}},
         else: {:error, :invalid_draft}
    else
      _ -> {:error, :invalid_draft}
    end
  rescue
    _ -> {:error, :invalid_draft}
  end

  def normalize(_), do: {:error, :invalid_draft}

  def apply(user, attrs) do
    with {:ok, draft} <- normalize(attrs), {:ok, council} <- Councils.ensure(user.author_id) do
      saved = Councils.editable(council)
      fallback = Enum.find(saved.lists, & &1.fallback)
      # Match each draft list once, preserving repeated halls and the account's existing picks.
      {merged, remaining} =
        Enum.map_reduce(draft.lists, saved.lists, fn incoming, remaining ->
          match =
            Enum.find(remaining, fn l ->
              if incoming.fallback,
                do: l.fallback,
                else: !l.fallback && l.hall_id == incoming.hall_id && l.name == incoming.name
            end)

          members =
            Enum.uniq_by(
              incoming.members ++ if(match, do: match.members, else: []),
              & &1.author_id
            )
            |> Enum.reject(&(&1.author_id == user.author_id))

          updated = %{incoming | id: match && match.id, members: members}
          {updated, if(match, do: Enum.reject(remaining, &(&1.id == match.id)), else: remaining)}
        end)

      final = Enum.find(merged, & &1.fallback) || fallback

      lists =
        Enum.reject(merged, & &1.fallback) ++ Enum.reject(remaining, & &1.fallback) ++ [final]

      Councils.save(user, %{version: council.version, lists: lists})
    end
  end

  defp valid_member?(m),
    do:
      is_integer(m.author_id) and
        (is_nil(m.reason) or (is_binary(m.reason) and String.length(m.reason) <= 5_000)) and
        (is_nil(m.source_url) or
           (is_binary(m.source_url) and String.length(m.source_url) <= 2_000))
end
