defmodule YouCongressWeb.InvitationLive do
  use YouCongressWeb, :live_view

  alias YouCongress.Invitations
  alias YouCongress.Invitations.Invitation

  def render(assigns) do
    ~H"""
    <.header class="text-center">
      Invite a friend
      <:subtitle>Invite Twitter users to YouCongress</:subtitle>
    </.header>
    <div class="space-y-12 divide-y">
      <div>
        <.simple_form
          for={@invite_form}
          id="invite_form"
          phx-submit="invite_twitter_username"
          phx-change="validate_twitter_username"
        >
          <.input
            field={@invite_form[:twitter_username]}
            type="text"
            label="Twitter username"
            data-lpignore="true"
            placeholder="@elonmusk"
            required
          />
          <:actions>
            <.button phx-disable-with="Changing...">Invite</.button>
          </:actions>
        </.simple_form>
      </div>
    </div>
    """
  end

  def mount(_params, session, socket) do
    current_user = YouCongress.Accounts.get_user_by_session_token(session["user_token"])

    {:ok,
     assign(socket,
       current_user: current_user,
       invite_form: new_invite_form(current_user)
     )}
  end

  defp new_invite_form(current_user) do
    %Invitation{}
    |> Invitation.changeset(%{user_id: current_user.id})
    |> to_form()
  end

  def handle_event("validate_twitter_username", params, socket) do
    %{"invitation" => %{"twitter_username" => twitter_username}} = params

    invite_form =
      %Invitation{}
      |> Invitation.changeset(%{
        twitter_username: twitter_username,
        user_id: socket.assigns.current_user.id
      })
      |> Map.put(:action, :validate)
      |> to_form()

    {:noreply, assign(socket, invite_form: invite_form)}
  end

  def handle_event("invite_twitter_username", params, socket) do
    %{"invitation" => %{"twitter_username" => twitter_username}} = params
    current_user = socket.assigns.current_user

    case Invitations.create_invitation(%{
           twitter_username: twitter_username,
           user_id: current_user.id
         }) do
      {:ok, invitation} ->
        info = "@#{invitation.twitter_username} has been invited"

        {:noreply,
         socket |> put_flash(:info, info) |> assign(invite_form: new_invite_form(current_user))}

      {:error, changeset} ->
        error_message = YouCongressWeb.ErrorHelpers.extract_errors(changeset)
        error = "Error inviting @#{twitter_username}: #{error_message}"
        {:noreply, socket |> put_flash(:error, error)}
    end
  end
end
