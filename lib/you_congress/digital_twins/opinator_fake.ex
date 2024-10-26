defmodule YouCongress.DigitalTwins.OpinatorFake do
  def generate_opinion(_topic, _model, _next_response, _name) do
    opinion = %{
      "name" => Faker.Person.name(),
      "bio" => Faker.Lorem.sentence(),
      "agree_rate" => "Strongly agree",
      "opinion" => Faker.Lorem.sentence(),
      "wikipedia_url" => Faker.Internet.url(),
      "twitter_username" => Faker.Internet.user_name(),
      "country" => Faker.Address.country()
    }

    {:ok, %{opinion: opinion, cost: 0}}
  end
end
