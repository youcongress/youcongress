defmodule YouCongress.OpinatorWorker.GeneratingLeftServer do
  @moduledoc """
  Decreases the number of opinions left each second.
  """
  use GenServer

  @name :generating_left_server
  # ms
  @update_interval 1000

  alias YouCongress.Votings

  def start_link(_) do
    GenServer.start_link(__MODULE__, nil, name: @name)
  end

  def init(_) do
    # Schedule the first update after @update_interval milliseconds
    Process.send_after(self(), :update_votings, @update_interval)
    {:ok, empty_state()}
  end

  def decrease_generating_left(voting_id) do
    GenServer.cast(@name, {:decrease_generating_left, voting_id})
  end

  def handle_cast({:decrease_generating_left, voting_id}, state) do
    new_state = Map.update(state, voting_id, 1, &(&1 + 1))
    {:noreply, new_state}
  end

  def handle_info(:update_votings, state) do
    Enum.each(state, fn {voting_id, num_to_decrese} ->
      case Votings.get_voting(voting_id) do
        nil ->
          nil

        voting ->
          generating_left = voting.generating_left - num_to_decrese
          Votings.update_voting(voting, %{generating_left: generating_left})
      end
    end)

    # Schedule the next update
    Process.send_after(self(), :update_votings, @update_interval)

    {:noreply, empty_state()}
  end

  defp empty_state, do: %{}
end
