defmodule YouCongress.Workers.UpdateAuthorPublicFigureWorker do
  @moduledoc """
  Marks an author as a public figure.

  Enqueued when an opinion with a source_url is created for an author
  who is not yet marked as a public figure.
  """

  use Oban.Worker, unique: [states: [:scheduled, :available]]

  alias YouCongress.Authors
  alias YouCongress.Authors.Author
  alias YouCongress.Repo

  @impl true
  def perform(%Oban.Job{args: %{"author_id" => author_id}}) do
    case Repo.get(Author, author_id) do
      %Author{public_figure: true} ->
        :ok

      %Author{} = author ->
        Authors.update_author(author, %{public_figure: true})
        :ok

      nil ->
        :ok
    end
  end
end
