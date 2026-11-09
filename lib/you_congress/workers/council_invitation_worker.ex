defmodule YouCongress.Workers.CouncilInvitationWorker do
  @moduledoc "Delivers one requested Council invitation; no follow-up campaign."
  use Oban.Worker, max_attempts: 3, unique: [period: :infinity]
  import Swoosh.Email
  alias YouCongress.{Repo, Mailer}
  alias YouCongress.Councils.{Invitation, Invitations}
  @impl true
  def perform(%Oban.Job{args: %{"invitation_id" => id}}) do
    case Repo.get(Invitation, id) do
      %Invitation{status: "sent"} -> :ok
      nil -> :ok
      invitation -> deliver(invitation)
    end
  end

  defp deliver(invitation) do
    user = Repo.get!(YouCongress.Accounts.User, invitation.user_id) |> Repo.preload(:author)

    if YouCongress.Accounts.Permissions.blocked?(user) do
      {:cancel, "Sender is unavailable"}
    else
      name = user.author.name || "A friend"

      email =
        new()
        |> to(invitation.email)
        |> from({"YouCongress", "hello@youcongress.org"})
        |> subject("#{name} invited you to choose your Council")
        |> text_body("""
        #{name} would like to see who you trust on YouCongress.

        #{invitation.note}

        Choose your Council: #{Invitations.url(user.author_id)}

        Your Council stays private. You can choose to publish separate, named lists of people.
        This is one invitation, with no follow-ups.
        If you weren't expecting this invitation, you can ignore it.
        """)

      case Mailer.deliver(email) do
        {:ok, _} ->
          invitation |> Ecto.Changeset.change(status: "sent") |> Repo.update!()
          :ok

        {:error, reason} ->
          {:error, reason}
      end
    end
  end
end
