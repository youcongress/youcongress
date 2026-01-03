defmodule YouCongressWeb.UserSessionController do
  use YouCongressWeb, :controller

  alias YouCongress.Accounts
  alias YouCongress.Accounts.User
  alias YouCongressWeb.UserAuth
  alias YouCongress.Accounts.Permissions

  def create(conn, %{"_action" => "registered"} = params) do
    create(conn, params, "Account created successfully!")
  end

  def create(conn, %{"_action" => "password_updated"} = params) do
    conn
    |> put_session(:user_return_to, ~p"/settings")
    |> create(params, "Password updated successfully!")
  end

  def create(conn, params) do
    create(conn, params, "Welcome back!")
  end

  defp create(conn, %{"user" => user_params}, info) do
    %{"email" => email, "password" => password} = user_params

    user = Accounts.get_user_by_email(email)

    cond do
      user && Permissions.blocked?(user) ->
        # Check password to avoid timing attacks
        _ = User.valid_password?(user, password)

        conn
        |> put_flash(
          :error,
          "Your account has been blocked as it seemed spam. If you're a real person or a useful bot, please contact support@youcongress.org if this is an error."
        )
        |> redirect(to: ~p"/log_in")

      user = Accounts.get_user_by_email_and_password(email, password) ->
        # Handle Pending Actions
        if pending_json = user_params["pending_actions"] do
          case Jason.decode(pending_json) do
            {:ok, %{"delegate_ids" => ids, "votes" => votes}} ->
              # Delegates
              for id <- ids do
                YouCongress.Delegations.create_delegation(user, id)
              end

              # Votes
              Enum.each(votes, fn {_statement_id, vote_data} ->
                if vote_data["answer"] && vote_data["answer"] != "" do
                  # We don't care about result
                  case YouCongress.Votes.create_or_update(%{
                         statement_id: vote_data["statement_id"],
                         answer: String.to_existing_atom(vote_data["answer"]),
                         author_id: user.author_id,
                         direct: true
                       }) do
                    _ -> :ok
                  end
                end
              end)

            _ ->
              :ok
          end
        end

        conn
        |> put_flash(:info, info)
        |> UserAuth.log_in_user(user, user_params)

      true ->
        # In order to prevent user enumeration attacks, don't disclose whether the email is registered.
        conn
        |> put_flash(:error, "Invalid email or password")
        |> put_flash(:email, String.slice(email, 0, 160))
        |> redirect(to: ~p"/log_in")
    end
  end

  def delete(conn, _params) do
    conn
    |> put_flash(:info, "Logged out successfully.")
    |> UserAuth.log_out_user()
  end
end
