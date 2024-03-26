Application.put_env(:you_congress, :hall_classifier, YouCongress.Halls.ClassificationFake)

ExUnit.start()
Ecto.Adapters.SQL.Sandbox.mode(YouCongress.Repo, :manual)
ExUnit.configure(exclude: :openai_api)
