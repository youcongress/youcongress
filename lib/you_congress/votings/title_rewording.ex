defmodule YouCongress.Votings.TitleRewording do
  def generate_rewordings(prompt, model) do
    implementation().generate_rewordings(prompt, model)
  end

  defp implementation do
    Application.get_env(
      :you_congress,
      :title_rewording_implementation,
      YouCongress.Votings.TitleRewordingAI
    )
  end
end
