---
name: youcongress-topic-quotes
description: Find quotes on the internet that are not already present on YouCongress, validate them, and add them to YouCongress through MCP tools, linking each quote to an existing YouCongress statement. Use for requests to add sourced quotes from experts, public figures, or notable institutions about a topic, all existing statements matching a topic, one specific statement, or a list of statement IDs. Use only authors who have no opinion already on the target statement, and do not repeat authors.
---

# YouCongress Topic Quotes

## Overview

Find candidate quotes on the public internet that are not already present on YouCongress, then add them to YouCongress via MCP tools and link each quote to an existing relevant statement. Support both single-quote and bulk requests; when the user gives a number, continue until that many valid non-duplicate quotes have been added or no more usable candidates can be found.

The target must come from the user's request or the skill invocation. The target can be a topic, one statement ID, several statement IDs, a statement title, or a request such as "all existing statements about `<topic>`." If no topic or statement target is provided, ask for one before using YouCongress write tools.

Author eligibility is mandatory: find and add quotes from authors who have no opinion already on this YouCongress statement. Don't repeat authors.

For author selection, prefer subject-matter experts with directly relevant credentials, such as researchers, academics, technical practitioners, or officials with domain responsibility. When suitable expert sources are scarce, use other eligible authoritative sources, including relevant journalists, institutional leaders, advocates, or notable organizations. Do not block a well-supported quote solely because its eligible author is not an expert.

Source-author quality is mandatory: only use quotes from subject-matter experts, public officials, elected leaders, judges, regulators, executives, researchers, academics, journalists, authors, advocates, institutional leaders, notable organizations, named declarations/open letters, or other public figures with relevant expertise, authority, or public accountability. Every quote must map to exactly one YouCongress author. Prefer one natural person or one organization. Use a collective text, declaration, open letter, or manifesto as the author only when the document itself has a distinct public identity and the quoted text is presented as the collective position of that named entity, for example `The Pro-Human AI Declaration`, and only when it is directly relevant to the target statement. In that case, create or reuse an author for the named collective text or declaration. Do not use posts, essays, reports, scientific papers, preprints, letters, or petitions whose quote would need to be attributed to multiple named people, a loose list of signatories, or an ambiguous author group. Do not use quotes from anonymous people, pseudonymous accounts, Reddit commenters, forum commenters, YouTube/TikTok/Instagram commenters, generic social-media users, customer reviews, poll respondents, or other private individuals whose relevance is only that they expressed an opinion online.

Do not default to quotes that support a statement. Treat `for`, `against`, and `abstain` as equally eligible outcomes when each is supported by a valid quote. Aim for a balanced mix of positions on each statement, but add any strong, eligible position when that is what the available evidence supports.

Do not call `quotes_verify`, `opinion_statements_verify`, or `votes_verify` in this workflow. You are adding a candidate quote, not verifying it.

If YouCongress admin MCP tools are not already loaded, use tool discovery for tools such as `quotes_list`, `statements_list`, `quotes_search`, `authors_search`, `authors_create`, `opinions_create`, and `opinions_statements_add`.

Use parallelism whenever searches or reads are independent: batch web searches, batch source fetches, and parallel YouCongress duplicate/author lookups. Do not parallelize dependent writes for the same candidate; create the opinion first, then link it.

## Workflow

### 0. Capture the target

Identify the requested target exactly enough to search YouCongress statements and external sources. A target can be:

- one topic such as `AI copyright lawsuits`, `carbon capture subsidies`, or `drug price negotiation`
- multiple topics in one request
- one statement ID or a list of statement IDs
- "all existing statements about" a topic

Use provided topics as search constraints, not as permission to create new statements. Every quote must fit an existing statement.

If the user provides statement IDs, target only those statements unless they also ask for related statements. If the user names a specific statement, target that statement first. If the user gives only a broad topic, build a working set of existing statements about that topic.

### 1. Inventory YouCongress first

Use `quotes_list` to get the most recent 100 YouCongress quotes so you do not add the same quote again.

Use `statements_list` to identify existing statements about the provided topic and see how many quotes each has. Prefer statements that are explicitly about the topic's complete claim, policy, event, actor, or controversy rather than statements that merely share a broad theme.

When the topic is broad, build a short list of candidate statements and search for quotes that can clearly support, oppose, or abstain on one of those existing statements. Prefer statements with fewer high-quality quotes only after relevance is clear.

Do not create a new statement. The quote must fit an existing statement.

If no existing statement matches the provided topic, stop and report that the topic has no usable existing statement. Do not search for a quote that would require creating a new statement.

For bulk work, search each candidate statement with `quotes_search` using the statement title, key author names, distinctive phrases, and topic terms. Keep a local inventory of existing opinion IDs, quote text, authors, source URLs, vote answers, and authors already represented on each statement for duplicate checks and author eligibility.

### 2. Build a parallel source-search plan

Search the public internet for real quotes from notable public figures, subject-matter experts, institutions, witnesses, officials, researchers, journalists, or authors about the topic and at least one candidate existing statement. Search subject-matter experts first; expand to other eligible authoritative authors when expert sources are scarce. Only use quotes that are absent from YouCongress and from authors who have no opinion already on the target YouCongress statement. Do not repeat authors within the current task. If the user specifies a recency window, enforce it using today's date from the environment; otherwise do not impose a freshness limit.

Avoid sources whose quoted speaker is merely a commenter or ordinary participant, even if the quote is easy to verify. Reddit threads, comment sections, forum posts, product reviews, and anonymous or pseudonymous social posts are not usable quote sources unless the author is independently identifiable as an expert or public figure and the account/source is attributable to them.

Avoid multi-author source attribution. A source is usable only when the exact quote can be attributed to one eligible author record: one person, one organization, or one named collective document/entity. Do not use a quote from a scientific paper, preprint, blog post, article, report, petition, or open letter if the only honest attribution is multiple people or a list of coauthors/signatories. The exception is a named collective document or campaign with its own public identity and a clear collective voice; treat that named entity, not the individual signatories, as the author.

Prefer primary sources: speeches, testimony, interviews, official press releases, official reports, hearing transcripts, court filings, government pages, campaign statements, verified official social posts, or direct media transcripts.

Useful source families depend on the topic and statement, but often include:

- official hearing transcripts and written testimony
- single-author scientific papers or preprints only when the quoted passage is attributable to that one author, plus reports and institutional or company news releases attributable to one organization
- government, regulator, court, legislative, and international-organization documents
- interviews, essays, op-eds, books, newsletters, or podcasts by named experts, journalists, policymakers, executives, advocates, or other relevant public figures
- credible blog posts or newsletters only when the author is identifiable as an expert or public figure and the source contains the exact quote

Generate many search queries at once. Combine the user's topic terms, statement titles, distinctive entities, named actors, key verbs, and likely position words. For statement-ID requests, read the statement titles first, then build searches from each statement's exact claim plus domain-specific terms from the statement.

Fetch and read every source page before using it. Do not rely on search snippets.

### 3. Create a candidate queue

For bulk requests, maintain a queue with:

- quote text
- author
- source URL and source label
- publication date and precision
- candidate statement ID/title
- proposed vote answer
- validation status
- duplicate-check status
- author-on-statement status

Track the queue's `for`, `against`, and `abstain` counts. Do not prioritize `for` quotes over other supported positions. Prefer a balanced set across the three answers when the available evidence supports it, but do not delay or reject a strong candidate merely because its vote is already common. Do not add weak quotes just to balance votes or reach a target count.

### 4. Validate before using write tools

Confirm all of the following before creating anything:

- the source URL contains the exact quote, allowing only faithful translation or `[...]` for omitted text
- the quote is attributed to exactly one eligible author record: one person, one organization, or one named collective document/entity
- the author is an expert, public figure, notable institution, or otherwise has relevant expertise, authority, or public accountability
- if the author is a named declaration, open letter, manifesto, or similar collective text, the source presents the quote as that entity's collective position and the entity is directly relevant to the target statement
- the quote is not from a source whose attribution would honestly require multiple named coauthors, signatories, or contributors
- the publication date is known precisely enough for `date_precision`
- any user-specified recency window is satisfied
- the quote concerns the provided topic and the candidate existing statement, not only a nearby broader issue
- the quote expresses a clear policy position or argumentative stance, not just a factual observation
- the quote is suitable as a standalone quote
- the author does not already have an opinion linked to the candidate statement
- the author has not already been used for another quote in the current task

If any check fails, discard the candidate and start again.

### 5. Check YouCongress for duplicates

Use `quotes_search` before creating anything.

Search globally and, once likely statements are known, search likely related statements. Query:

- the author name
- distinctive quote phrases
- key terms from the quote
- topic-specific terms from the source and the matched statement

If the same or substantially identical quote already exists, start again and find a different quote.

If the same author already has any opinion on the candidate statement, start again and find a different author. For bulk work, also discard later candidates by authors already selected or added in the current task, even when the quote text is different.

For bulk work, run duplicate checks in parallel for multiple validated candidates, then remove duplicates from the queue before any writes.

### 6. Find the best matching existing statement

Use `statements_list` and any available statement search tools to find an existing YouCongress statement that the quote addresses.

A quote qualifies only if it either:

- is directly about the complete statement; or
- is about something else, but clearly implies that the author supports, opposes, or abstains on the complete statement.

The author's position on the complete statement must be clear from the quote alone. Do not accept a quote that only relates to one word, theme, subtopic, or nearby issue unless it also implies the author's position on the complete statement. Do not infer a position from general sentiment, party membership, job title, institutional role, or facts outside the quote.

If no existing statement fits clearly, discard the candidate and find a different quote. Do not force the quote onto a weakly related statement.

### 7. Infer the vote from the quote alone

Infer the answer from the quote alone; never select a quote merely because it supports the statement. Choose:

- `for` if the quote clearly supports the complete statement
- `against` if the quote clearly opposes the complete statement
- `abstain` if the quote explicitly expresses neutrality, uncertainty, mixed views, or refusal to take a side

If the vote would require outside context or interpretation, discard the candidate and find another quote.

### 8. Find or create the author

Use `authors_search`. Reuse an existing author if present.

Only find and add authors who have no opinion already on this youcongress statement. Don't repeat authors.

Only use `authors_create` if no matching author exists. Use the public figure's, expert's, institution's, or named collective text's common name and accurate identifying details supported by the source or reliable public information. For a named declaration, open letter, manifesto, or similar collective entity, create the author for the named text/entity itself, not for the individual signatories, and only when the source supports that the quote is the collective position of that entity. Do not create authors for Reddit users, forum handles, anonymous or pseudonymous accounts, customer reviewers, poll respondents, ordinary private individuals, ad hoc groups of coauthors, lists of signatories, or multi-author papers/posts unless they are independently identifiable as one organization or one named collective entity relevant to the statement.

For bulk work, run `authors_search` in parallel for candidates that passed source validation and duplicate checks.

### 9. Create and link

Use `opinions_create` with the exact quote, source URL, author, date, and `date_precision`. Use the most precise publication date supported by the source.

Then use the YouCongress MCP tool `opinions_statements_add` with the statement ID and inferred `vote_answer`.

For bulk work, process writes candidate-by-candidate. After each successful `opinions_create`, immediately link it with `opinions_statements_add` before moving to the next candidate, so partial progress remains coherent if a later candidate fails.

### 10. Final QA

Re-open or re-fetch the source and confirm:

- quote text is exact
- author is correct
- author maps to exactly one YouCongress author record, not multiple people or an ambiguous coauthor/signatory list
- author qualifies as an expert, public figure, notable institution, or other authoritative/publicly accountable source
- any named declaration, open letter, manifesto, or similar collective author has a distinct public identity and is directly relevant to the linked statement
- date and date precision are supported by the source
- any user-specified recency window is satisfied
- the statement is an existing statement about the provided topic and the quote addresses the complete statement
- the vote follows from the quote alone
- no duplicate was added
- the author had no prior opinion on the linked statement and was not repeated in this task

For bulk requests, report how many quotes were added, how many were rejected as duplicates or weak matches, and whether the requested target count was reached. If final QA fails for any created quote, report the issue and do not call verification tools to compensate.
