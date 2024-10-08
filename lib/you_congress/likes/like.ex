defmodule YouCongress.Likes.Like do
  @moduledoc """
  The Like schema.
  """

  use Ecto.Schema

  import Ecto.Changeset

  schema "likes" do
    field :opinion_id, :integer
    field :user_id, :integer

    timestamps()
  end

  @doc false
  def changeset(like, attrs) do
    like
    |> cast(attrs, [:opinion_id, :user_id])
    |> validate_required([:opinion_id, :user_id])
    |> unique_constraint([:opinion_id, :user_id], name: :likes_opinion_id_user_id_index)
  end
end
