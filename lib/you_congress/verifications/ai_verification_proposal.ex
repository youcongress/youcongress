defmodule YouCongress.Verifications.AIVerificationProposal do
  @moduledoc """
  An untrusted model recommendation awaiting explicit human review.
  """

  use Ecto.Schema
  import Ecto.Changeset

  schema "ai_verification_proposals" do
    field :subject, :string
    field :subject_id, :integer
    field :subject_snapshot, :map
    field :result, :map
    field :request_options, :map, default: %{}
    field :model, :string
    field :review_status, Ecto.Enum, values: [:pending, :approved, :rejected], default: :pending
    field :reviewed_at, :utc_datetime

    belongs_to :requested_by, YouCongress.Accounts.User
    belongs_to :reviewer, YouCongress.Accounts.User

    timestamps()
  end

  @type t :: %__MODULE__{}

  def changeset(proposal, attrs) do
    proposal
    |> cast(attrs, [
      :subject,
      :subject_id,
      :subject_snapshot,
      :result,
      :request_options,
      :model,
      :review_status,
      :requested_by_id,
      :reviewer_id,
      :reviewed_at
    ])
    |> validate_required([
      :subject,
      :subject_id,
      :subject_snapshot,
      :result,
      :model,
      :review_status,
      :requested_by_id
    ])
    |> validate_inclusion(:subject, ~w(quote relevance vote))
    |> foreign_key_constraint(:requested_by_id)
    |> foreign_key_constraint(:reviewer_id)
  end
end
