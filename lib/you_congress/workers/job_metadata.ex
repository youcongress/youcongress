defmodule YouCongress.Workers.JobMetadata do
  @moduledoc false

  require Logger

  def put(%Oban.Job{id: id} = job, key, value) when is_integer(id) and is_binary(key) do
    update(job, key, value)
  end

  def put(job_id, key, value) when is_integer(job_id) and is_binary(key) do
    update(job_id, key, value)
  end

  def put(_job, _key, _value), do: :ok

  def format_reason(reason) when is_atom(reason), do: Atom.to_string(reason)
  def format_reason(reason) when is_binary(reason), do: reason
  def format_reason(reason), do: inspect(reason, limit: 20, printable_limit: 500)

  defp update(job_or_id, key, value) do
    case Oban.update_job(job_or_id, fn persisted_job ->
           meta = Map.put(persisted_job.meta || %{}, key, value)
           %{meta: meta}
         end) do
      {:ok, _job} ->
        :ok

      {:error, reason} ->
        Logger.error("Failed to save Oban job metadata under #{inspect(key)}: #{inspect(reason)}")
        :ok
    end
  end
end
