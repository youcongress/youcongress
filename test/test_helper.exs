Application.put_env(:you_congress, :hall_classifier, YouCongress.Halls.ClassificationFake)
Application.put_env(:you_congress, :ai_replier, YouCongress.Opinions.AIReplier.AIReplierFake)

Application.put_env(
  :you_congress,
  :public_figures_generator,
  YouCongress.DigitalTwins.PublicFiguresFake
)

Application.put_env(
  :you_congress,
  :opinator_implementation,
  YouCongress.DigitalTwins.OpinatorFake
)

Application.put_env(
  :you_congress,
  :title_rewording_implementation,
  YouCongress.Votings.TitleRewordingFake
)

ExUnit.start()
Ecto.Adapters.SQL.Sandbox.mode(YouCongress.Repo, :manual)
ExUnit.configure(exclude: :openai_api)
