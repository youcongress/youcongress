# Quote Authenticity Verification

Use this guidance when deciding whether an existing YouCongress quote is authentic and correctly stored.

## Inputs

Use the quote data returned by `quotes_recent_unverified`, including author, date, source URL, source text, and quote content.

## Task

Verify whether the quote is authentic.

Confirm that the quote is real and verbatim, allowing `[...]` for omitted text and faithful translation, that it is correctly attributed to the author, and that the source URL contains it.

When no fetchable source URL is available but a source passage is provided, verify the quote against that passage instead. It is authentic when the quote appears in, or is a faithful rendering or translation of, the provided passage and the passage attributes it to the author. The provided passage replaces the web fetch you cannot perform for such sources; still use web search to corroborate the attribution where possible.

Treat named declarations, manifestos, open letters, petitions, collective statements, and similar collective texts as valid quote authors only when the source presents the quoted text as the wording of that named entity, the entity has its own clear public identity, and it is directly relevant to the statement at issue. Do not dispute a quote merely because the author is a document title rather than a single person or organisation when those conditions are met. Do not treat scientific papers, preprints, journal articles, reports, books, newsletters, websites, or other publications as quote authors to create or correct.

## Correction Guidance

Also check whether the stored content, date, source, and author are the right canonical values.

If the quote is authentic but any stored field is wrong and you can recover the right values from reliable evidence, return `disputed` and include the correct values in the comment: content, source URL or source text, date, date precision, and author metadata when relevant.

For author corrections, use exactly one author name only when the quote has one individual author, when an organisation is speaking on its own behalf, or when the source presents the quote as the text of one named declaration, manifesto, open letter, petition, joint statement, or similarly relevant collective text with its own clear public identity. In the collective-text case, use the document title, or the named issuing coalition if that is the canonical attribution, as the author. Do not create or correct an author to a scientific paper, preprint, journal article, report, book, newsletter, website, or other publication title. Use month or year date precision if exact dates conflict.

If a source merely lists multiple individual authors or signers and does not present a single organisation, coalition, or named document as the quoted author, do not return a correction. Return `disputed` and explain that the quote has multiple individual authors, which the platform cannot verify as a single-author quote.

## Statuses

Choose exactly one status:

- `ai_verified`: you confirmed the quote is real and correctly attributed.
- `disputed`: you found the quote is fabricated, materially altered, misattributed, or stored with a recoverable canonical-field error.
- `ai_unverifiable`: you could not find enough evidence either way.
- `unverifiable`: the quote cannot be checked in principle.

Always include a short comment citing what you found.
