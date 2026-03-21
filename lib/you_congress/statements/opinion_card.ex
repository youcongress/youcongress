defmodule YouCongress.Statements.OpinionCard do
  @moduledoc """
  Represents a statement+vote pair for display in the statements index.
  Used for round-robin ordering where each statement appears once before any repeats.
  """

  defstruct [:id, :statement, :vote, :round, votes_by_answer: %{}]

  @type t :: %__MODULE__{
          id: String.t(),
          statement: YouCongress.Statements.Statement.t(),
          vote: YouCongress.Votes.Vote.t(),
          round: integer(),
          votes_by_answer: %{optional(:for | :against | :abstain) => YouCongress.Votes.Vote.t()}
        }
end
