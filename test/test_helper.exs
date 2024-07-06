Application.put_env(:you_congress, :hall_classifier, YouCongress.Halls.ClassificationFake)
Application.put_env(:you_congress, :ai_replier, YouCongress.Opinions.AIReplier.AIReplierFake)

ExUnit.start()
Ecto.Adapters.SQL.Sandbox.mode(YouCongress.Repo, :manual)
ExUnit.configure(exclude: :openai_api)
