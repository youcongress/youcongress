defmodule YouCongressWeb.ClusterUtils do
  @moduledoc """
  Helper module for cluster operations.
  """

  def find_session_owner(module, function, args) do
    # Ask all other nodes
    nodes = Node.list()

    # We use :erpc.multicall to check all nodes in parallel
    {results, _bad_nodes} = :erpc.multicall(nodes, module, function, args)

    # Find the first one that returned {:ok, instance_id}
    Enum.find_value(results, fn
      {:ok, instance_id} -> {:ok, instance_id}
      _ -> nil
    end)
  end
end
