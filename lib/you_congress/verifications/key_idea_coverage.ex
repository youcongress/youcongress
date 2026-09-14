defmodule YouCongress.Verifications.KeyIdeaCoverage do
  @moduledoc """
  Shared acceptance rules for quote coverage of a complete statement.

  AI-generated candidates must explicitly attest that every material idea in the
  statement is covered by the quoted words. The structured evidence is a hard
  ingestion/matching gate; downstream verification still independently judges
  the quote and the statement link.
  """

  @doc """
  Returns true only for a candidate that explicitly reports complete coverage
  and supplies non-empty evidence for each material idea.
  """
  def valid?(candidate) when is_map(candidate) do
    all_covered = get(candidate, "all_key_ideas_covered")
    coverage = get(candidate, "key_idea_coverage")
    missing = get(candidate, "missing_key_ideas")

    all_covered == true and is_list(coverage) and coverage != [] and
      Enum.all?(coverage, &valid_item?/1) and missing in [nil, []]
  end

  def valid?(_candidate), do: false

  @doc """
  Applies `valid?/1` and confirms that every claimed evidence string actually
  occurs in the stored quote.
  """
  def valid?(candidate, quote) when is_map(candidate) and is_binary(quote) do
    valid?(candidate) and
      Enum.all?(get(candidate, "key_idea_coverage"), fn item ->
        quote
        |> normalize_text()
        |> String.contains?(item |> get("evidence") |> normalize_text())
      end)
  end

  def valid?(_candidate, _quote), do: false

  @doc """
  Prevents a relevance or vote result from being accepted when its structured
  coverage evidence does not pass `valid?/1`.
  """
  def enforce_verification_result("relevance", %{"status" => "ai_verified"} = result) do
    if valid?(result) do
      result
    else
      result
      |> Map.put("status", "disputed")
      |> append_comment("Rejected because not every material key idea is covered by the quote.")
    end
  end

  def enforce_verification_result("vote", %{"correct_answer" => answer} = result)
      when answer in ~w(for against abstain) do
    if valid?(result) do
      result
    else
      result
      |> Map.put("correct_answer", "none")
      |> append_comment(
        "No vote accepted because not every material key idea is covered by the quote."
      )
    end
  end

  def enforce_verification_result(_subject, result), do: result

  @doc """
  Prompt text shared by quote discovery, matching, and verification.
  """
  def prompt_instructions do
    """
    Apply a strict key-idea coverage gate. First decompose the COMPLETE statement
    into every material idea: actor, action, object, scope, timing, conditions,
    and qualifiers such as high-stakes, internal, frontier, comparative, or
    quantitative terms. The quote itself must express every material idea or a
    faithful linguistic equivalent. Source context may resolve a pronoun or
    shorthand, but it may not supply a missing actor, action, object, scope,
    timing, condition, or qualifier. A quote about the same topic, a broader or
    narrower claim, or only one subtopic fails. Set all_key_ideas_covered to true
    only when every material idea is covered, and list one key_idea_coverage item
    per material idea with the idea and the exact quote wording that supports it.
    If any idea is missing or only appears in surrounding source context, reject
    the candidate. When the schema includes missing_key_ideas, list every missing
    material idea there and leave it empty only when coverage is complete.
    """
  end

  defp valid_item?(item) when is_map(item) do
    present?(get(item, "idea")) and present?(get(item, "evidence"))
  end

  defp valid_item?(_item), do: false

  defp get(map, "all_key_ideas_covered"),
    do: Map.get(map, "all_key_ideas_covered") || Map.get(map, :all_key_ideas_covered)

  defp get(map, "key_idea_coverage"),
    do: Map.get(map, "key_idea_coverage") || Map.get(map, :key_idea_coverage)

  defp get(map, "missing_key_ideas"),
    do: Map.get(map, "missing_key_ideas") || Map.get(map, :missing_key_ideas)

  defp get(map, "idea"), do: Map.get(map, "idea") || Map.get(map, :idea)
  defp get(map, "evidence"), do: Map.get(map, "evidence") || Map.get(map, :evidence)

  defp append_comment(result, message) do
    comment = Map.get(result, "comment")

    Map.put(
      result,
      "comment",
      if(present?(comment), do: String.trim(comment) <> " " <> message, else: message)
    )
  end

  defp present?(value) when is_binary(value), do: String.trim(value) != ""
  defp present?(_value), do: false

  defp normalize_text(value) do
    value
    |> String.downcase()
    |> String.replace(~r/\s+/, " ")
    |> String.trim()
  end
end
