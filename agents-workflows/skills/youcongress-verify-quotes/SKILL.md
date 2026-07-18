---
name: youcongress-verify-quotes
description: Verify one or more recent unverified YouCongress quotes and their linked statement stances, using parallel validation for independent quotes when possible. Use when asked to check quote authenticity, source attribution, opinion-statement relevance, unlink contradicted quote or relevance associations, or vote answers for existing YouCongress opinions by using quotes_recent_unverified, quotes_verify, opinion_statements_verify, opinions_statements_remove, and votes_verify MCP tools.
allowed-tools:
  - web.search_query
  - web.open
  - web.find
---

# YouCongress Verify Quotes

## Overview

Verify existing YouCongress quote records end to end. Start from `quotes_recent_unverified`, then complete every pending verification on each returned record: quote authenticity, opinion-statement relevance, and vote answer. Every returned record has at least one pending verification, but its quote may already be `ai_verified`; quote-level `ai_verified` confirms authenticity only, not relevance links or votes. If an upstream record is already verified, do not repeat that specific check: treat it as passing and continue to every downstream relevance or vote check that is still unverified. Preserve statement associations when quote authenticity is `ai_unverifiable`; unlink them only when quote authenticity is contradicted or unverifiable in principle.

If YouCongress MCP tools are not already loaded, use tool discovery for `quotes_recent_unverified`, `quotes_verify`, `opinion_statements_verify`, `opinions_statements_remove`, `votes_verify`, `opinions_statements_add`, and `opinions_show`.

Run independent quote validations in parallel whenever the environment supports parallel tool calls or subagents. Preserve the dependency order inside each quote: quote authenticity gates relevance checks, and relevance gates vote checks.

## Required References

Read the relevant reference before each validation pass:

- Quote authenticity: [references/quote.md](references/quote.md)
- Opinion-statement relevance: [references/relevance.md](references/relevance.md)
- Vote answer: [references/vote.md](references/vote.md)

These references mirror the validation guidance from `YouCongress.Verifications.VerifierAI`; do not substitute looser criteria.

## Workflow

1. Call `quotes_recent_unverified`.
2. Treat the returned list as the full work set for this run. If the user requested 100 quotes, verify 100 only when `quotes_recent_unverified` returns 100 records; if it returns fewer records, such as 3, verify only those returned records.
3. If it returns no quote, do nothing else: do not run searches, do not call verification tools, and report that there are no recent unverified quotes, relevance links, or votes available.
4. Build a work queue from all returned quotes. For each quote, run only its still-pending verification types: quote authenticity when the quote status is pending, relevance when a linked statement's relevance status is pending and the quote passed, and vote verification when its quote and relevance passed and the vote status is pending. Do not skip a returned quote solely because its quote-authenticity status is already `ai_verified`.
5. Initialize run-level counters before processing: quotes seen, quotes already `ai_verified`, quotes newly marked `ai_verified`, quotes marked `disputed`, quotes marked `ai_unverifiable`, quotes marked `unverifiable`, statement links already `ai_verified`, statement links newly marked `ai_verified`, statement links marked `ai_unverifiable`, statement links unlinked, votes already `ai_verified`, votes newly marked `ai_verified`, vote mismatches found, author-mismatched vote associations re-linked, author-mismatched vote associations left unrepaired, and checks skipped because an upstream gate failed.
6. Process separate quotes in parallel. When subagents are available, assign each worker a disjoint set of `opinion_id`s and tell workers not to mutate records outside that set. When only local parallel tool calls are available, parallelize source fetches, searches, and independent MCP verification writes across different `opinion_id`s.
7. For each returned quote, inspect the quote, relevance, and vote verification statuses to identify pending work and update the appropriate counters for already-verified downstream records.
8. If the quote's `verification_status` is already `ai_verified`, do not call `quotes_verify`; count it as already verified, treat quote authenticity as passing, and continue to every linked statement. Inspect each link's relevance status and, after relevance passes, its vote status. `ai_verified` on the quote must never be treated as verification of those separate records.
9. If the quote's `verification_status` is not `ai_verified`, validate the returned quote against [references/quote.md](references/quote.md), then call `quotes_verify` with `opinion_id`, `status`, `comment`, and `model`; increment the counter for the stored result.
10. If the resulting quote status is `ai_unverifiable`, preserve every current statement association, increment skipped-check counters for blocked downstream work, and skip relevance and vote checks for that quote. If the resulting quote status is `disputed` or `unverifiable`, call `opinions_statements_remove` for every currently linked `statement_id` on that opinion, increment the unlinked counter for each removed association, increment skipped-check counters for blocked downstream work, and skip relevance and vote checks for that quote. Do not preserve an existing statement association for a quote that is `disputed` or `unverifiable`, even if that association was previously marked `ai_verified`.
11. For every statement linked to a verified quote, inspect `relevance_status`.
12. Validate multiple linked statements for the same verified quote in parallel when they are independent.
13. If the relevance status is already `ai_verified`, do not call `opinion_statements_verify`; count it as already verified, treat relevance as passing, and continue to vote verification.
14. If the relevance status is not `ai_verified`, validate relevance against [references/relevance.md](references/relevance.md).
15. If relevance is confirmed, call `opinion_statements_verify` with `opinion_id`, `statement_id`, `status: "ai_verified"`, `comment`, and `model`, then increment the newly-verified relevance counter.
16. If relevance is contradicted and the result would be `disputed`, do not call `opinion_statements_verify`; call `opinions_statements_remove` with `opinion_id` and `statement_id`, increment the unlinked counter, then skip vote verification for that statement.
17. If relevance evidence is insufficient and the result would be `ai_unverifiable`, call `opinion_statements_verify` with `opinion_id`, `statement_id`, `status: "ai_unverifiable"`, `comment`, and `model`, increment that counter, then skip vote verification for that statement.
18. For every linked vote whose quote and relevance checks passed, inspect `vote.verification_status`.
19. Validate multiple vote answers in parallel when they are attached to already verified quote-statement pairs.
20. If the vote status is already `ai_verified`, do not call `votes_verify`; count it as already verified and report it as already verified.
21. If the vote status is not `ai_verified`, first validate the existing relevance link and vote answer against [references/vote.md](references/vote.md), including vote-author ownership. Do not change a usable association before attempting these checks.
22. Preserve the existing association when its relevance can be verified and its vote can be verified as-is: call `votes_verify` with `vote_id`, `status: "ai_verified"`, `comment`, and `model`. An author-ID difference alone is not permission to re-link before this attempt.
23. Re-link only when the existing association cannot be verified as-is (for example, ownership prevents vote verification, the association is unusable, or the recorded vote cannot be verified) and a replacement is necessary to complete verification. Determine the correct answer first, then call `opinions_statements_remove` and `opinions_statements_add` for only that same `opinion_id`/`statement_id`, with `trigger_relevance_verification: false`. Confirm the replacement with `opinions_show`, re-run relevance verification, and verify its vote only when the replacement is valid. If the existing association can be verified, or replacement fails, leave it in place and report the result; do not remove it merely to normalize ownership.
24. If the recorded vote answer does not match, do not call `votes_verify`; increment the vote mismatch counter, report the mismatch and correct answer, and apply step 23 only if a replacement is necessary and feasible. Otherwise leave the association unchanged.
25. Stop after processing the records returned by the initial `quotes_recent_unverified` call for this run. Do not call `quotes_recent_unverified` again to top up a short batch to the requested number.

## Parallel Execution

Use parallelism for independent work, not for dependent gates:

- Fetch and inspect source pages for different quotes concurrently.
- Validate quote authenticity for different `opinion_id`s concurrently.
- After a quote is verified, validate its separate statement links concurrently.
- After each quote-statement link is verified, validate its separate votes concurrently.
- Keep writes idempotent and record-scoped: each verification call should target exactly one `opinion_id`, `statement_id`, or `vote_id`. Re-link only after the existing relevance and vote have been attempted and cannot be verified as-is; any repair must affect only the same quote-author opinion-statement pair.
- Do not let multiple workers verify, remove, or report on the same `opinion_id`/`statement_id`/`vote_id` pair.
- If parallel workers return conflicting conclusions, pause writes for the affected record, inspect the sources locally, and store only the locally resolved result.

## Pass Criteria

Treat a pass as:

- quote or relevance: `status` is `ai_verified`
- vote: the independently verified `correct_answer` matches the recorded vote answer; the verification status to store is `ai_verified`

Do not verify downstream records after an upstream failure. Already verified upstream records count as passing; continue to any downstream unverified records:

- If the quote is `ai_unverifiable`, call `quotes_verify` with that status, preserve every currently linked statement association, and skip relevance and vote checks for that quote.
- If the quote is `disputed` or `unverifiable`, call `quotes_verify` with that status, then call `opinions_statements_remove` for every currently linked statement and skip relevance and vote checks for that quote.
- If relevance is confirmed off-topic, adjacent, or otherwise contradicted, call `opinions_statements_remove` instead of marking the relevance link `disputed`, then skip vote verification for that statement.
- If relevance cannot be determined because evidence is insufficient, call `opinion_statements_verify` with `status: "ai_unverifiable"`, then skip vote verification for that statement.
- If an existing relevance link or vote cannot be verified as-is, re-link only when a replacement is necessary and can be confirmed; otherwise preserve the existing association and report why it could not be verified.
- If the vote answer does not match, do not call `votes_verify`; report the mismatch and the correct answer.

Use `ai_unverifiable` when evidence is insufficient, `disputed` when quote authenticity contradicts the stored record, and `unverifiable` only when the record cannot be checked in principle. For quote authenticity failures and for quote-statement relevance contradictions, unlink with `opinions_statements_remove` instead of preserving the association.

## Verification Discipline

Use web search and source inspection for each check. Prefer primary sources and the stored `source_url`; when the source cannot be fetched but `source_text` is supplied, use that passage as the cited source context and search only to corroborate attribution where possible.

Keep comments short but evidentiary: cite the source, quote wording, source context, or inference that justifies the result. Include the model identifier used for the validation.

Do not fabricate source access. If the linked source cannot be inspected and no adequate source passage is present, mark the relevant pass `ai_unverifiable`. When the quote itself is `ai_unverifiable`, preserve every current statement association and skip downstream checks; remove associations only when the quote is `disputed` or `unverifiable`.

## Output

Start with an aggregate summary of the run that reports counts for at least:

- quotes seen
- quotes already `ai_verified`
- quotes newly marked `ai_verified`
- quotes marked `disputed`
- quotes marked `ai_unverifiable`
- quotes marked `unverifiable`
- statement links already `ai_verified`
- statement links newly marked `ai_verified`
- statement links marked `ai_unverifiable`
- statement links unlinked
- votes already `ai_verified`
- votes newly marked `ai_verified`
- vote mismatches found
- author-mismatched vote associations re-linked
- author-mismatched vote associations left unrepaired
- checks skipped because an upstream validation failed

Summarize each processed quote with:

- quote opinion ID and author
- quote-authenticity status
- each linked statement ID and relevance status
- each statement preserved because the quote was `ai_unverifiable`
- each statement unlinked because the quote was `disputed` or `unverifiable`
- each statement unlinked because relevance was contradicted
- each vote ID and vote verification result or mismatch
- each association re-linked only because it could not be verified as-is, including the reason, replacement vote, renewed relevance result, and any failed repair step
- any checks skipped because an upstream validation failed
