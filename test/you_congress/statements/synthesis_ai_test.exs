defmodule YouCongress.Statements.SynthesisAITest do
  use ExUnit.Case, async: true

  alias YouCongress.Authors.Author
  alias YouCongress.Opinions.Opinion
  alias YouCongress.Statements.Statement
  alias YouCongress.Statements.SynthesisAI
  alias YouCongress.Votes.Vote

  defp vote(id, answer, opts \\ []) do
    %Vote{
      answer: answer,
      opinion: opinion(id, opts),
      alternate_opinions: Keyword.get(opts, :alternates, [])
    }
  end

  defp opinion(id, opts \\ []) do
    %Opinion{
      id: id,
      content: Keyword.get(opts, :content, "Quote number #{id}."),
      author: %Author{
        id: id,
        name: "Author #{id}",
        bio: Keyword.get(opts, :bio),
        description: nil,
        twitter_username: nil
      }
    }
  end

  defp statement, do: %Statement{title: "AI should have legal personhood"}

  defp count_occurrences(string, substring),
    do: length(:binary.matches(string, substring))

  test "serializes one JSON line per quote with the vote's stance" do
    votes = [vote(1, :for), vote(2, :against)]

    prompt = SynthesisAI.prompt(statement(), votes)

    assert prompt =~ "Statement: AI should have legal personhood"
    assert prompt =~ "Below are 2 sourced quotes"
    assert prompt =~ ~s("opinion_id":1)
    assert prompt =~ ~s("author":"Author 1")
    assert prompt =~ ~s("stance":"for")
    assert prompt =~ ~s("stance":"against")
    assert prompt =~ ~s("quote":"Quote number 1.")
    refute prompt =~ "representative sample"
  end

  test "includes alternate quotes under the same stance, deduplicated" do
    main = opinion(1)
    votes = [vote(1, :for, alternates: [main, opinion(11)]), vote(2, :against)]

    prompt = SynthesisAI.prompt(statement(), votes)

    # The main opinion appears once despite also being listed as an alternate.
    assert count_occurrences(prompt, ~s("opinion_id":1,)) == 1
    assert prompt =~ ~s("opinion_id":11)
    # The alternate inherits its vote's stance.
    assert count_occurrences(prompt, ~s("stance":"for")) == 2
  end

  test "truncates long quote content" do
    long = String.duplicate("a", 600)
    votes = [vote(1, :for, content: long)]

    prompt = SynthesisAI.prompt(statement(), votes)

    assert prompt =~ String.duplicate("a", 500) <> " […]"
    refute prompt =~ String.duplicate("a", 501)
  end

  test "caps the prompt at 150 quotes, keeping minority stances" do
    votes =
      Enum.map(1..400, &vote(&1, :for)) ++
        Enum.map(401..403, &vote(&1, :against)) ++
        Enum.map(404..406, &vote(&1, :abstain))

    prompt = SynthesisAI.prompt(statement(), votes)

    assert prompt =~ "150 sourced quotes"
    assert prompt =~ "(a representative sample of 406 in total)"
    assert count_occurrences(prompt, ~s("opinion_id":)) == 150
    # Both minority stances survive the sampling in full.
    assert count_occurrences(prompt, ~s("stance":"against")) == 3
    assert count_occurrences(prompt, ~s("stance":"abstain")) == 3
  end
end
