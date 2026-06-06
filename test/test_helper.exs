Application.put_env(:you_congress, :hall_classifier, YouCongress.Halls.ClassificationFake)

Application.put_env(
  :you_congress,
  :title_rewording_implementation,
  YouCongress.Statements.TitleRewordingFake
)

Application.put_env(
  :you_congress,
  :quotator_implementation,
  YouCongress.Opinions.Quotes.QuotatorFake
)

Application.put_env(
  :you_congress,
  :author_country_inference_implementation,
  YouCongress.Authors.CountryInferenceFake
)

ExUnit.start()
Ecto.Adapters.SQL.Sandbox.mode(YouCongress.Repo, :manual)
ExUnit.configure(exclude: :openai_api)
