defmodule YouCongress.DigitalTwins.Opinator do
  def generate_opinion(topic, model, nextresponse, name) do
    implementation().generate_opinion(topic, model, nextresponse, name)
  end

  defp implementation do
    Application.get_env(
      :you_congress,
      :opinator_implementation,
      YouCongress.DigitalTwins.OpinatorAI
    )
  end
end
