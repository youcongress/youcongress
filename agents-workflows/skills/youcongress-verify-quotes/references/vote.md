# Vote Answer Verification

Use this guidance when deciding whether a linked vote answer is correct after quote authenticity and relevance have passed.

## Task

Determine the author's position on the statement based on the quote and, when needed, the cited source article's context around the quote.

Use the statement title, source URL, source passage for non-web sources, quote content, and current recorded answer.

## Vote Author Ownership

Confirm that the vote's author is the quote's author before verifying it. A vote owned by another author cannot be verified against this quote.

First attempt to verify the existing relevance link and vote as they are. Preserve the association when both checks can pass. Do not re-link solely because the vote author differs from the quote author.

Re-link only if the existing association cannot be verified as-is (including an ownership mismatch that blocks vote verification) and replacing it is necessary to complete the check. Determine the answer independently, then remove and re-add only that same opinion-statement pair. Inspect the replacement and re-verify its relevance before verifying its vote. If repair fails, leave the existing association in place and report the failed step. When the determined answer is `none`, do not call `votes_verify`.

## Classification Guidance

Based on what the quote says and how the cited source presents it, decide the author's most likely position on the whole statement. Use the linked page when a source URL is provided, otherwise use the source passage.

A position may be explicit in the quote, strongly implied by the quote's ordinary meaning, or stated in the cited source article or passage while the stored quote gives the author's comment, criticism, concern, argument, reason, or explanation for that position.

When a source URL is provided, use web search to inspect the source page when the quote is context-dependent; otherwise rely on the source passage.

Do not require the quote to restate every part of the statement or amount to strict logical proof. When one position is substantially more likely than the alternatives, classify it as that position and explain the inference in the comment.

For example, a prediction that AI will create a labor shortage strongly implies support for the statement "AI will create more jobs than it destroys", even though it does not explicitly compare jobs created and destroyed.

## Answers

Choose exactly one correct answer:

- `for`: the quote explicitly or strongly implies support for the statement.
- `against`: the quote explicitly or strongly implies opposition to the statement.
- `abstain`: the quote is explicitly neutral or undecided on the statement.
- `none`: no position is substantially more likely because the quote is genuinely ambiguous, merely adjacent to the issue, or missing a necessary connection to the statement in both the quote and its cited source context.

Do not choose `none` merely because some reasonable inference is required.

Always include a short comment justifying the answer with the quote's wording and, when used, the cited source context. If the position is implied rather than explicit in the stored quote, identify that inference and any limitation in the evidence.

## Verification Result

Compare the correct answer with the current recorded answer.

- If they match, vote verification passes and `votes_verify` may be called.
- If they do not match, vote verification fails. Do not call `votes_verify`; report the recorded answer, the correct answer, and the evidence.
