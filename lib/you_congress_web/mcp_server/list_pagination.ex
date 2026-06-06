defmodule YouCongressWeb.MCPServer.ListPagination do
  @moduledoc """
  Shared cursor pagination for *_list MCP tools: order by id ("desc" by default,
  or "asc") and an optional last_id cursor to fetch the next page.
  """

  def order(params) do
    case Map.get(params, :order, "desc") do
      "asc" -> :asc
      _ -> :desc
    end
  end

  def maybe_paginate(opts, params) do
    case Map.get(params, :last_id) do
      nil ->
        opts

      last_id ->
        case order(params) do
          :asc -> Keyword.put(opts, :id_greater_than, last_id)
          :desc -> Keyword.put(opts, :id_less_than, last_id)
        end
    end
  end

  def last_id([]), do: nil
  def last_id(records), do: List.last(records).id
end
