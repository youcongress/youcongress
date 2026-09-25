defmodule YouCongress.Verifications.Verification do
  @moduledoc """
  Schema for opinion verifications.
  """

  use Ecto.Schema
  import Ecto.Changeset

  alias YouCongress.ContentLimits

  schema "verifications" do
    field :status, Ecto.Enum,
      values: [
        :verified,
        :ai_verified,
        :ai_unverifiable,
        :endorsed,
        :disputed,
        :unverifiable,
        :unverified
      ]

    field :comment, :string
    field :model, :string, default: "human"

    belongs_to :opinion, YouCongress.Opinions.Opinion
    belongs_to :user, YouCongress.Accounts.User

    timestamps()
  end

  def changeset(verification, attrs) do
    verification
    |> cast(attrs, [:opinion_id, :user_id, :status, :comment, :model])
    |> validate_required([:opinion_id, :user_id, :status])
    |> ContentLimits.validate_text(:comment, 4_000, 8_000)
    |> ContentLimits.validate_text(:model, 100, 400)
    |> foreign_key_constraint(:opinion_id)
    |> foreign_key_constraint(:user_id)
  end
end
