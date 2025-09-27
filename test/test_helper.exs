Application.put_env(:you_congress, :hall_classifier, YouCongress.Halls.ClassificationFake)

Application.put_env(
  :you_congress,
  :title_rewording_implementation,
  YouCongress.Votings.TitleRewordingFake
)

Application.put_env(
  :you_congress,
  :voting_generator,
  YouCongress.Votings.GeneratorFake
)

Application.put_env(
  :you_congress,
  :quotator_implementation,
  YouCongress.Opinions.Quotes.QuotatorFake
)

ExUnit.start()
Ecto.Adapters.SQL.Sandbox.mode(YouCongress.Repo, :manual)
ExUnit.configure(exclude: :openai_api)
