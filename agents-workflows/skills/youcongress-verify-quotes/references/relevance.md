# Opinion-Statement Relevance Verification

Use this guidance when deciding whether a verified quote is relevant to one linked statement.

## Task

Verify whether the quote is relevant to the complete statement and provides enough signal that the author's stance on the complete statement is determinable. This relevance pass must not decide the final vote direction; the separate vote pass does that.

## Qualifying Relevance

A quote qualifies if it either:

- is directly about the complete statement's claim, proposal, or question;
- is a comment, criticism, concern, argument, reason, or explanation that the cited source presents as part of the author's support, opposition, or abstention on the complete statement; or
- is about a narrower, causal, comparative, or underlying issue whose ordinary meaning, plus the cited source context when available, makes one stance on the complete statement substantially more likely than the alternatives.

Do not require the quote to restate every part of the complete statement, pin down every quantified, net, or comparative claim, or amount to strict logical proof. If the quote is on the same issue and strongly points toward a likely stance on the complete statement, mark it relevant and leave the exact `for`, `against`, or `abstain` classification to the vote pass.

For example, a quote arguing that AI investment is premised on employers replacing large shares of workers is relevant to "AI will create more jobs than it destroys": it strongly signals a determinable stance on net jobs even if it does not explicitly compare total jobs created and destroyed.

## Source Context

When a source URL is provided, use web search to inspect the source page when the quote is abstract, uses shorthand, or refers to "the proposal", "this", "these ideas", or similar context-dependent language. When no source URL is provided, use the source passage as the cited source context for the same purpose.

The clear support, opposition, or abstention may be stated elsewhere in the cited source article or passage rather than inside the stored quote itself, as long as the stored quote is one of the author's comments or reasons for that position.

Source context may establish what the quote is responding to. For example, if a source article is about a proposal to create AI-run non-human corporations, and the quote criticizes that idea as "programmed impunity" or responsibility shifted onto machines, treat the quote as relevant to a statement about granting AI agents legal personhood as non-human corporations.

## Rejection Rules

Do not accept a quote that only relates to one word, theme, subtopic, or nearby issue unless the quote plus its source context supplies the necessary connection and makes one stance on the complete statement substantially more likely.

Do not infer a position from general sentiment, party membership, job title, or facts outside the quote and its cited source context.

Do not accept a quote merely because the article discusses the statement; the cited source must connect this author's quoted comment or reason to the issue.

## Statuses

Choose exactly one status:

- `ai_verified`: the quote is on-topic for the complete statement and one of support, opposition, or abstention on the complete statement is substantially more likely, whether explicit or strongly implied.
- `disputed`: the quote is off-topic, merely adjacent, or no stance on the complete statement is substantially more likely.
- `ai_unverifiable`: you cannot tell.

Always include a short comment explaining the decision.
