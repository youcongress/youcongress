defmodule YouCongress.Opinions.Answers.Answer do
  @moduledoc """
  Define Answer schema
  """
  use Ecto.Schema
  import Ecto.Changeset

  alias YouCongress.Opinions.Opinion

  schema "answers" do
    field :response, :string
    has_many :opinions, Opinion

    timestamps()
  end

  def changeset(answer, attrs) do
    answer
    |> cast(attrs, [:response])
    |> validate_required([:response])
  end
end
