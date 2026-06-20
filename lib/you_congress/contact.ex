defmodule YouCongress.Contact do
  @moduledoc """
  Validates and delivers messages submitted through the contact form.
  """

  use Ecto.Schema

  import Ecto.Changeset
  import Swoosh.Email

  alias YouCongress.Mailer

  @primary_key false
  embedded_schema do
    field :name, :string
    field :email, :string
    field :website, :string
    field :subject, :string
    field :body, :string
  end

  @fields ~w(name email website subject body)a
  @required_fields ~w(name email subject body)a

  def changeset(contact, attrs \\ %{}) do
    contact
    |> cast(attrs, @fields)
    |> validate_required(@required_fields)
    |> validate_format(:email, ~r/\A[^\s]+@[^\s]+\z/,
      message: "must have the @ sign and no spaces"
    )
    |> validate_format(:website, ~r/\Ahttps?:\/\/[^\s]+\z/,
      message: "must be a valid http or https URL"
    )
    |> validate_format(:name, ~r/\A[^\r\n]+\z/, message: "must be on one line")
    |> validate_format(:subject, ~r/\A[^\r\n]+\z/, message: "must be on one line")
    |> validate_length(:name, max: 100)
    |> validate_length(:email, max: 160)
    |> validate_length(:website, max: 500)
    |> validate_length(:subject, max: 160)
    |> validate_length(:body, max: 10_000)
  end

  def deliver(%__MODULE__{} = contact) do
    new()
    |> to("hi@youcongress.org")
    |> from({"YouCongress", "hello@youcongress.org"})
    |> reply_to(contact.email)
    |> subject(contact.subject)
    |> text_body(
      "Name: #{contact.name}\nEmail: #{contact.email}\nWebsite or social media: #{contact.website || "Not provided"}\n\n#{contact.body}"
    )
    |> Mailer.deliver()
  end
end
