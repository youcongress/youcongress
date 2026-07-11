defmodule YouCongressWeb.StatementController do
  use YouCongressWeb, :controller

  alias YouCongress.Statements
  alias YouCongress.Statements.QuotesCsv

  def redirect_to_p(conn, %{"slug" => slug}) do
    redirect(conn, to: ~p"/p/#{slug}")
  end

  def quotes_csv(conn, %{"slug" => slug}) do
    statement = Statements.get_by!(slug: slug)

    conn
    |> put_resp_header("cache-control", "no-store")
    |> send_download({:binary, QuotesCsv.generate(statement)},
      filename: "youcongress-statement-#{statement.id}-#{statement.slug}-#{timestamp()}.csv",
      content_type: "text/csv"
    )
  end

  def all_quotes_csv(conn, _params) do
    conn
    |> put_resp_header("cache-control", "no-store")
    |> send_download({:binary, QuotesCsv.generate_all()},
      filename: "youcongress-dataset-#{timestamp()}.csv",
      content_type: "text/csv"
    )
  end

  defp timestamp, do: Calendar.strftime(DateTime.utc_now(), "%Y%m%d-%H%M%S")
end
