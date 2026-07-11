defmodule YouCongressWeb.StatementController do
  use YouCongressWeb, :controller

  alias YouCongress.Statements
  alias YouCongress.Statements.QuotesCsv

  def redirect_to_p(conn, %{"slug" => slug}) do
    redirect(conn, to: ~p"/p/#{slug}")
  end

  def quotes_csv(conn, %{"slug" => slug}) do
    statement = Statements.get_by!(slug: slug)

    send_download(conn, {:binary, QuotesCsv.generate(statement)},
      filename: "#{statement.slug}-quotes.csv",
      content_type: "text/csv"
    )
  end

  def all_quotes_csv(conn, _params) do
    send_download(conn, {:binary, QuotesCsv.generate_all()},
      filename: "dataset.csv",
      content_type: "text/csv"
    )
  end
end
