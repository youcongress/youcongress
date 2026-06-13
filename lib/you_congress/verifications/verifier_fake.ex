defmodule YouCongress.Verifications.VerifierFake do
  @moduledoc """
  Deterministic, network-free implementation of
  `YouCongress.Verifications.Verifier` for dev and tests.

  `submit/2` encodes the subject in the returned job id; `check_job_status/1`
  decodes it and returns a positive, completed result so the whole cascade can be
  exercised offline. Tests that need other branches (e.g. a disputed relevance)
  can configure their own stub module via `:quote_verifier_implementation`.
  """

  @behaviour YouCongress.Verifications.Verifier

  @impl true
  def submit(subject_type, %{id: id}), do: {:ok, "fake:#{subject_type}:#{id}"}

  @impl true
  def check_job_status("fake:vote:" <> _id) do
    {:ok, :completed, %{"correct_answer" => "for", "comment" => "Fake verification", "model" => "fake-llm"}}
  end

  def check_job_status("fake:" <> _rest) do
    {:ok, :completed, %{"status" => "ai_verified", "comment" => "Fake verification", "model" => "fake-llm"}}
  end

  def check_job_status(_job_id), do: {:ok, :in_progress}
end
