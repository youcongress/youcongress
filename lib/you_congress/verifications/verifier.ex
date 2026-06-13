defmodule YouCongress.Verifications.Verifier do
  @moduledoc """
  Submits AI verification jobs to an LLM and polls for their result.

  There are three subjects: a quote's authenticity (`:quote`), a quote's
  relevance to a statement (`:relevance`) and a vote's answer (`:vote`).

  The implementation is swappable via the `:quote_verifier_implementation` config
  key. It defaults to the OpenAI-backed `VerifierAI`; dev (without an API key) and
  tests use `VerifierFake`.
  """

  @type subject_type :: :quote | :relevance | :vote
  @type result :: %{optional(String.t()) => term()}

  @callback submit(subject_type, struct()) :: {:ok, String.t()} | {:error, term()}
  @callback check_job_status(String.t()) ::
              {:ok, :completed, result()} | {:ok, :in_progress} | {:error, term()}

  @spec submit(subject_type, struct()) :: {:ok, String.t()} | {:error, term()}
  def submit(subject_type, subject), do: implementation().submit(subject_type, subject)

  @spec check_job_status(String.t()) ::
          {:ok, :completed, result()} | {:ok, :in_progress} | {:error, term()}
  def check_job_status(job_id), do: implementation().check_job_status(job_id)

  defp implementation do
    Application.get_env(
      :you_congress,
      :quote_verifier_implementation,
      YouCongress.Verifications.VerifierAI
    )
  end
end
