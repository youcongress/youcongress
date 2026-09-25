defmodule YouCongress.ContentLimitsTest do
  use YouCongress.DataCase, async: true

  alias YouCongress.Authors.Author
  alias YouCongress.OpinionStatementVerifications.OpinionStatementVerification
  alias YouCongress.Opinions.Opinion
  alias YouCongress.Statements.Statement
  alias YouCongress.Verifications.Verification
  alias YouCongress.VoteVerifications.VoteVerification

  test "opinion text has character and byte ceilings" do
    character_changeset =
      Opinion.changeset(%Opinion{}, %{
        content: String.duplicate("a", 10_001),
        source_text: String.duplicate("s", 50_001),
        twin: false
      })

    assert %{content: [_], source_text: [_]} = errors_on(character_changeset)

    byte_changeset =
      Opinion.changeset(%Opinion{}, %{
        content: String.duplicate("🙂", 6_000),
        twin: false
      })

    assert %{content: [message]} = errors_on(byte_changeset)
    assert message =~ "bytes"
  end

  test "author biographies are bounded in regular and profile changesets" do
    oversized_bio = String.duplicate("🙂", 3_000)

    assert %{bio: [message]} =
             %Author{}
             |> Author.changeset(%{twin_origin: true, name: "Author", bio: oversized_bio})
             |> errors_on()

    assert message =~ "bytes"

    assert %{bio: [_]} =
             %Author{}
             |> Author.profile_changeset(%{bio: oversized_bio}, [:bio])
             |> errors_on()
  end

  test "all verification comments share the same bounded size" do
    oversized_comment = String.duplicate("a", 4_001)

    changesets = [
      Verification.changeset(%Verification{}, %{comment: oversized_comment}),
      OpinionStatementVerification.changeset(%OpinionStatementVerification{}, %{
        comment: oversized_comment
      }),
      VoteVerification.changeset(%VoteVerification{}, %{comment: oversized_comment})
    ]

    assert Enum.all?(changesets, fn changeset ->
             match?(%{comment: [_]}, errors_on(changeset))
           end)
  end

  test "statement titles and URLs are bounded" do
    changeset =
      Statement.changeset(%Statement{}, %{
        title: String.duplicate("t", 501),
        url: "https://example.com/" <> String.duplicate("u", 2_100)
      })

    assert %{title: [_], url: [_ | _]} = errors_on(changeset)
  end
end
