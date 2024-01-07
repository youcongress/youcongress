# Script for populating the database. You can run it as:
#
#     mix run priv/repo/seeds.exs
#
# Inside the script, you can read and write to any of your
# repositories directly:
#
#     YouCongress.Repo.insert!(%YouCongress.SomeSchema{})
#
# We recommend using the bang functions (`insert!`, `update!`
# and so on) as they will fail if something goes wrong.

alias YouCongress.Votes.Answers

Answers.basic_response_answer_id_map()
|> Map.keys()
|> Enum.each(fn response ->
  {:ok, _} = Answers.create_answer(%{response: response})
end)
