defmodule YouCongressWeb.TrustController do
  use YouCongressWeb, :controller
  alias YouCongress.TrustRankings

  def removed(conn, _params), do: send_resp(conn, 404, "Not found")

  def public_lists(conn, %{"author_id" => id}), do: redirect(conn, to: ~p"/a/#{id}/lists")

  def person(conn, %{"id" => raw} = params) do
    author =
      case TrustRankings.parse_id(raw) do
        nil -> nil
        id -> YouCongress.Repo.get(YouCongress.Authors.Author, id)
      end

    if author do
      path =
        if params["tab"] == "statements",
          do: YouCongressWeb.AuthorPaths.profile(author),
          else: YouCongressWeb.AuthorPaths.trust(author)

      conn |> put_status(:moved_permanently) |> redirect(to: path)
    else
      send_resp(conn, 404, "This person is not available.")
    end
  end

  def simplified(conn, _params) do
    redirect(conn,
      to:
        if(YouCongress.Accounts.admin?(conn.assigns[:current_user]),
          do: ~p"/trust",
          else: ~p"/council"
        )
    )
  end

  def export(conn, %{"id" => id}) do
    case TrustRankings.get_snapshot(id) do
      nil -> send_resp(conn, 404, "Snapshot not found")
      snapshot -> csv(conn, snapshot.result["rows"], snapshot.result["participants"])
    end
  end

  def export(conn, %{"scope" => scope} = params) do
    result = TrustRankings.ranking(scope, params)
    csv(conn, result.rows, result.participants)
  end

  defp csv(conn, rows, participants) do
    values =
      Enum.map(rows, fn row ->
        Enum.map([:rank, :name, :count, :share], fn key ->
          safe_cell(Map.get(row, key, row[to_string(key)]))
        end) ++ [participants]
      end)

    content =
      NimbleCSV.RFC4180.dump_to_iodata([
        ["Rank", "Person", "Nominations", "Share (%)", "Participants"] | values
      ])

    conn
    |> put_resp_content_type("text/csv")
    |> put_resp_header("content-disposition", "attachment; filename=trust-ranking.csv")
    |> send_resp(200, content)
  end

  defp safe_cell(value) when is_binary(value) do
    if String.starts_with?(value, ["=", "+", "-", "@", "\t", "\r"]), do: "'" <> value, else: value
  end

  defp safe_cell(value), do: value

  def unsubscribe(conn, %{"token" => token}) do
    case Phoenix.Token.verify(YouCongressWeb.Endpoint, "trust-digest", token, max_age: 31_536_000) do
      {:ok, author_id} ->
        import Ecto.Query

        YouCongress.Repo.update_all(
          from(c in YouCongress.Councils.Council, where: c.author_id == ^author_id),
          set: [digest: "off"]
        )

        text(
          conn,
          "Email updates are now off. You can turn them on again in your council settings."
        )

      _ ->
        send_resp(conn, 400, "This unsubscribe link is invalid or expired.")
    end
  end
end
