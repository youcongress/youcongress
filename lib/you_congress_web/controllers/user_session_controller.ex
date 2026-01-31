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
    create(conn, params, nil)
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
        handle_pending_actions(user, user_params["pending_actions"])
        conn = if info, do: put_flash(conn, :info, info), else: conn
        UserAuth.log_in_user(conn, user, user_params)

      true ->
        # In order to prevent user enumeration attacks, don't disclose whether the email is registered.
        conn
        |> put_flash(:error, "Invalid email or password")
        |> put_flash(:email, String.slice(email, 0, 160))
        |> redirect(to: ~p"/log_in")
    end
  end

  defp handle_pending_actions(_user, nil), do: :ok

  defp handle_pending_actions(user, pending_json) do
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
            create_pending_vote(user, vote_data)
          end
        end)

      _ ->
        :ok
    end
  end

  defp create_pending_vote(user, vote_data) do
    YouCongress.Votes.create_or_update(%{
      statement_id: vote_data["statement_id"],
      answer: String.to_existing_atom(vote_data["answer"]),
      author_id: user.author_id,
      direct: true
    })
  rescue
    _ -> :ok
  end

  def delete(conn, _params) do
    conn
    |> put_flash(:info, "Logged out successfully.")
    |> UserAuth.log_out_user()
  end
end
