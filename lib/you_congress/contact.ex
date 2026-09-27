defmodule YouCongress.Contact do
  @moduledoc """
  Validates and delivers messages submitted through the contact form.
  """

  use Ecto.Schema

  import Ecto.Changeset
  import Swoosh.Email

  require Logger

  alias YouCongress.Mailer

  @contact_email "hello@youcongress.org"

  @primary_key false
  embedded_schema do
    field :name, :string
    field :email, :string
    field :website, :string
    field :subject, :string
    field :body, :string
  end

  @fields ~w(name email website subject body)a
  @required_fields ~w(name email body)a

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
    |> validate_length(:subject, max: 200)
    |> validate_length(:body, max: 10_000)
  end

  def deliver(%__MODULE__{} = contact) do
    email =
      new()
      |> to(@contact_email)
      |> from({"YouCongress", @contact_email})
      |> reply_to(contact.email)
      |> subject(contact.subject || "Contact form by #{contact.name}")
      |> text_body(
        "Name: #{contact.name}\nEmail: #{contact.email}\nWebsite or social media: #{contact.website || "Not provided"}\n\n#{contact.body}"
      )

    case Mailer.deliver(email) do
      {:ok, metadata} = result ->
        Logger.info("Contact email accepted by mailer: #{inspect(metadata)}")
        result

      {:error, reason} = result ->
        Logger.error("Contact email delivery failed: #{inspect(reason)}")
        result
    end
  end
end
