# Script for populating the database. You can run it as:
#
#     mix run priv/repo/seeds.exs
#

defmodule YouCongress.Seeds do
  alias YouCongress.Accounts
  alias YouCongress.Authors
  alias YouCongress.Statements
  alias YouCongress.Opinions
  alias YouCongress.Votes

  def run do
    user = create_user()

    if user do
      authors = create_authors(%{name: "Admin", bio: "YCO admin"})
      statements = create_statements(user)
      create_opinions_and_votes(user, authors, statements)
    end
  end

  defp create_user do
    email = "admin@youcongress.org"
    password = "admin:1234"

    if user = Accounts.get_user_by_email(email) do
      IO.puts("User #{email} already exists.")
      user
    else
      case Accounts.register_user(%{"email" => email, "password" => password}) do
        {:ok, %{user: user}} ->
          IO.puts("User #{email} created successfully.")

          case Accounts.update_role(user, "admin") do
            {:ok, updated_user} ->
              IO.puts("User #{email} role updated to admin.")
              updated_user

            {:error, changeset} ->
              IO.inspect(changeset, label: "Failed to update role")
              user
          end

        {:error, changeset} ->
          IO.inspect(changeset, label: "Failed to create user")
          nil
      end
    end
  end

  defp create_authors do
    [
      "Stuart J. Russell",
      "Demis Hassabis",
      "Scott Alexander",
      "Yoshua Bengio",
      "Eliezer Yudkowsky",
      "Yann LeCun",
      "Geoffrey Hinton",
      "Gary Marcus",
      "Dario Amodei",
      "Sam Altman",
      "Elon Musk",
      "Max Tegmark"
    ]
    |> Enum.map(fn name ->
      case Authors.find_by_name_or_create(%{
             "name" => name,
             "bio" => Faker.Person.title()
           }) do
        {:ok, author} ->
          IO.puts("Author #{name} created/found successfully.")
          author

        {:error, changeset} ->
          IO.inspect(changeset, label: "Failed to create author #{name}")
          nil
      end
    end)
    |> Enum.reject(&is_nil/1)
  end

  defp create_statements(user) do
    polls = [
      "Create a global institute for AI safety, similar to CERN",
      "Mandatory third-party audits for major AI systems",
      "Require AI systems above a capability threshold to be interpretable",
      "Ban autonomous lethal weapons",
      "Ban open-source AI models capable of creating WMDs"
    ]

    Enum.map(polls, fn poll ->
      case Statements.create_statement(%{
             "title" => poll,
             "user_id" => user.id
           }) do
        {:ok, statement} ->
          IO.puts("Statement #{statement.title} created successfully.")
          statement

        {:error, %{errors: [title: {"has already been taken", _}]} = _changeset} ->
          IO.puts("Statement #{poll} already exists, fetching...")
          Statements.get_by(title: poll)

        {:error, changeset} ->
          IO.inspect(changeset, label: "Failed to create statement #{poll}")
          nil
      end
    end)
    |> Enum.reject(&is_nil/1)
  end

  defp create_opinions_and_votes(user, authors, statements) do
    for author <- authors, statement <- statements do
      opinion_attrs = %{
        "content" => Faker.Lorem.sentence(5..15),
        "twin" => false,
        "author_id" => author.id,
        "user_id" => user.id
      }

      case Opinions.create_opinion(opinion_attrs) do
        {:ok, %{opinion: opinion}} ->
          IO.puts("Opinion for #{author.name} on '#{statement.title}' created.")

          case Opinions.add_opinion_to_statement(opinion, statement, user.id) do
            {:ok, _} ->
              IO.puts("Opinion linked to statement.")

              vote_attrs = %{
                "direct" => true,
                "twin" => false,
                "author_id" => author.id,
                "statement_id" => statement.id,
                "answer" => Enum.random([:for, :against, :abstain]),
                "opinion_id" => opinion.id
              }

              case Votes.create_vote(vote_attrs) do
                {:ok, _vote} -> IO.puts("Vote cast by #{author.name}.")
                {:error, changeset} -> IO.inspect(changeset, label: "Failed to create vote")
              end

            {:error, reason} ->
              IO.inspect(reason, label: "Failed to link opinion to statement")
          end

        {:error, changeset} ->
          IO.inspect(changeset, label: "Failed to create opinion")
      end
    end
  end
end

YouCongress.Seeds.run()
