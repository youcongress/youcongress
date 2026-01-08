defmodule YouCongressWeb.ClusterUtils do
  @moduledoc """
  Helper module for cluster operations.
  """

  def find_session_owner(module, function, args) do
    # Ask all other nodes
    nodes = Node.list()

    {results, _bad_nodes} = :rpc.multicall(nodes, module, function, args)

    Enum.find_value(results, fn
      {:ok, instance_id} -> {:ok, instance_id}
      _ -> nil
    end)
  end
end
