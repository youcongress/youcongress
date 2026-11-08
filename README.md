# YouCongress

[YouCongress.org](https://youcongress.org) is a non-profit, open-source and open-data platform for building source-grounded knowledge bases around hard public questions. It has two connected but distinct layers:

- **Data layer:** a provenance-preserving ingestion and structure layer that turns public discourse into inspectable quote–claim records.
- **Participation layer (beta):** a liquid-democracy interface for direct votes, optional delegation, and policy discussion.

The project’s first large focus is AI governance, safety, regulation, labour impacts, compute governance, and international coordination. The data model and workflow are designed to generalize to any question where it matters who said what, in what source, and how that passage bears on a claim or proposal.

## The data layer

YouCongress is not a truth-scoring system, an expert-representativeness survey, or a measure of how much evidential weight a speaker deserves. It is a reusable substrate for research and assessment: humans and downstream systems can inspect, challenge, correct, and extend records without having to repeat the entire ingestion process.

Each sourced quote record keeps the original material separate from derived annotations. Where available, it includes:

- the verbatim quotation, attributed author, original source, publication date, and date precision;
- one or more normalized statements—claims or policy proposals—to which the quotation is relevant;
- a passage-level stance on each linked statement: **For**, **Abstain/unclear**, or **Against**;
- independent verification histories for source fidelity, quote–statement relevance, and stance.

The quote remains the primary artifact. A reviewer can revise a relevance link or stance label without rewriting the quote or losing its provenance. A quote may link to several statements; exports therefore use one row per quote–statement link.

### Ingestion and verification

The application workflow and larger scheduled coding-agent jobs converge on the same records. Both use distinct passes for discovery, attribution, statement linking, stance inference, source-fidelity checking, relevance checking, and stance checking:

> source discovery → quote extraction and attribution → statement linking + stance inference → source-fidelity check → quote–statement relevance check → stance check → export

Verification is progressive: a stance cannot be verified before the quote and its relation to the statement have passed their respective checks. “AI verified” means an automated verifier found support for the annotation; it is not blinded human validation, and agreement among automated passes is not independent evidence. Humans can review records in the UI, and authors can claim profiles through X to update or delete their quotations. See the [agent workflow guide](agents-workflows/README.md) for implementation detail.

### Access and reuse

- Download the [complete CSV dataset](https://youcongress.org/dataset.csv), or export sourced quotes from an individual statement page. The complete export includes statements with at least three verified quotes.
- Browse and query public records through the no-key [MCP endpoint](https://youcongress.org/mcp). See the [MCP tool documentation](https://youcongress.org/mcp-tools) for setup and available tools.
- Logged-in users can create scoped API keys for authenticated MCP tools that contribute, edit, and verify records.
- The application code is licensed under the [MIT License](LICENSE). YouCongress’s structured annotations and metadata are released under [CC BY 4.0](https://creativecommons.org/licenses/by/4.0/), with attribution to YouCongress. Quoted third-party material and author bios remain subject to their original rights holders; each record links to its source.

### What the data layer does not yet solve

The corpus reflects its source discovery, search terms, agents, and time periods; it is not a census of public or expert belief. Record counts are not polls or truth estimates, and several quotes drawn from one hearing, article, panel, or institutional publication are correlated rather than independent.

Known next steps include retaining search logs and negative results; adding `source_event_id` to expose shared-event clusters; strengthening entity resolution, alias merging, and duplicate review; and extending the deliberately coarse stance labels with confidence, conditions, argument roles, and explicit uncertainty. Automated checks also need calibration through stratified, blinded human audits that report human–human and AI–human agreement, class-specific errors, and representative disagreements.

## Participation layer (beta)

The participation layer uses the sourced record as a transparent input to policy deliberation. Citizens can search topics, inspect sources, vote directly, delegate to users they trust, and add opinions. Public figures can appear as delegates where their stance is inferred from sourced quotes. These interfaces make preferences legible, but neither vote totals nor quote totals determine truth or representative support; those require attention to provenance, argument quality, expertise, dependence among sources, and missing perspectives.

## Case studies

The workflow has also been used to build collections for three epistemic case studies:

- [COVID-19 origins](https://youcongress.org/h/covid-19-origins): 800+ sourced quotations across several claims.
- [Eggs and health](https://youcongress.org/h/eggs-and-health): 500+ sourced quotations across several claims.
- [LHC safety](https://youcongress.org/p/lhc-poses-no-risk-to-earth): 180+ sourced quotations on whether the LHC presents a credible risk to Earth.

## About

YouCongress is built by [Hector Perez Arenas](https://www.linkedin.com/in/hectorperezarenas/), who leads an AI engineering team in Madrid and organizes the Madrid Elixir meetup. He also builds open-source knowledge and civic-tech systems, including [Notes.club](https://notes.club), which hosts more than 10,000 Elixir notebooks. Follow him on [Bluesky](https://bsky.app/profile/hecperez.com) or [X](https://x.com/arpahector).

## How to start

Install dependencies:

```bash
mix deps.get
```

Create the database, the user `admin@youcongress.org` with password `admin:1234`, and sample data:

```bash
mix ecto.setup
```

Run the server:

```bash
mix phx.server
```

Open [http://localhost:4000](http://localhost:4000) in your browser.

## How to contribute

Run `mix check` while developing. It formats the code, compiles with warnings treated as errors, builds assets, runs strict Credo checks and tests, and scans for security issues with Sobelow.

Before committing, run `mix precommit`. It first audits dependencies for retirements and security advisories, then runs the same checks without rewriting formatting and with test coverage. `mix ci` runs the same checks as `mix precommit`.

All three commands use the test environment and the test database configured in `config/test.exs`. Install dependencies with `mix deps.get` and make sure PostgreSQL is running. Dependency auditing requires Hex 2.5.1 or newer (`mix local.hex` to update) and network access. Sobelow runs locally without update checks and fails on findings at any confidence level or source parsing errors. Coverage uses Mix's default 90% minimum; reports are written to `cover/`. Tests tagged `:openai_api` remain excluded.

The browser Content Security Policy is enforced on browser routes. Its allowlist supports the existing analytics, Turnstile, chart, form, and video integrations; Oban and LiveDashboard use a fresh request nonce for inline scripts. When adding a browser integration, update the policy and test it with enforcement enabled. Production HTTPS handling trusts Fly's `x-forwarded-proto` header, so the application must remain behind that trusted proxy.

Sobelow honors only the documented, check-specific `sobelow_skip` annotations for reviewed parameterized SQL, escaped output, and the dynamically generated CSP. New findings still fail the scan, including low-confidence findings and parsing failures.

- Email hector@youcongress.org if you would like to help validate quotes found by AI agents.
- Take an [unassigned issue](https://github.com/youcongress/youcongress/issues).

## Acknowledgments

- [AppSignal](https://www.appsignal.com) for application monitoring.
- [Rocket Validator](https://rocketvalidator.com) for HTML and accessibility checks.

## Trust Network

Participants manage ordered private Council lists at `/council`. The four defaults are
AI governance, Impact on jobs, Environment, and General. Existing picks remain in the final
General list. Any existing hall can be added repeatedly, including extra General lists;
custom names distinguish small trusted groups. Lists can be reordered or removed, except
for the permanent final General list. Its people and name remain editable.

For each statement, only lists matching one of its hall tags are consulted, in saved order.
Every General list applies to every statement, including an extra General placed first.
The first matching list with more For than Against, or more Against than For, decides.
Abstentions, missing positions, and disputed/unverified evidence do not count toward the majority.
Ties (including zero For and zero Against) move on to the next matching list.
Lists are never pooled. If none decides, no delegated vote is recorded. Direct votes,
including Abstain, always override the result; delegation does not follow chains.
Source-inferred positions still need positive authenticity, relevance, and stance verification.
The existing “See how your Council voted” disclosure shows this sequence and each consulted
list’s people, without changing the surrounding statement page. Hall-tag changes queue
recalculation for affected Councils.

Signed-in topic edits, reasons, names, and order save automatically. Guest topic selections
and reasons survive signup; email signups take effect after confirmation. Publishing and
invitations remain optional. Hall selection is available inside Edit, not on the Council
overview. Each entry selects one owned private/public list or another author's public list.

`/lists` manages all named people lists. `people_lists.public` defaults to false, and
`people_list_members` stores each list's people, reasons, source URLs, and order.
`council_lists` stores only the private hall assignment, position, fallback flag, and
`people_list_id`. The same list can serve multiple entries or Councils. Editing an owned
list from either screen changes the same record and refreshes all dependent Council votes.
Reasons follow the list's visibility; publishing makes the list and its reasons public.
Private lists are accessible only to their owner. Public pages and MCP responses never
expose which Councils use a list. A user's own entry in a list is ignored by their Council.

Selecting someone else's public list follows its live membership and reasons without
edit permission. The picker also offers an independent private copy. If the source is
deleted or becomes private, other users' assignments become unavailable and evaluation
continues to the next matching entry. Owners can continue using their own private lists.
The picker can create a new private list directly. Existing lists autosave membership,
reasons, names, URLs, and visibility with optimistic version checks and visible errors.
Reasons save after a typing pause; URL edits save on blur. Navigation flushes pending edits.
Creating a list and publishing from Council retain explicit confirmation buttons.

Migration `20261108195000` keeps existing public lists public and converts unlinked Council
collections into private people lists. Existing linked lists become direct references;
any differing private Council notes are preserved in a separate private list. It preserves
reconsideration member references, removes the old membership/link tables, and queues vote
recalculation. A schema rollback requires a separate data-preserving migration.

Public list URLs use `/@username/lists/<slug>`, with `/a/<author_id>/lists/<slug>` as
an automatic fallback for authors without a username. Slugs are suggested from the list
name and editable during creation, Council publishing, and later edits. They are unique
per author; previous slugs remain reserved for their list and redirect to its current URL.
Legacy `/lists/<id>` links redirect permanently. Renaming a list does not change its slug
unless the author edits the URL field. Existing lists receive name-based slugs with their
ID appended during migration, preserving all numeric links.

`/trust` (also `/trust/general`) shows the single global YouCongress Trust 30 and its positions
on statements. While participation grows, rankings, snapshots, exports, and MCP ranking
access are restricted to admins. Public Council pages do not show ranking previews or links.
Public reasons live at `/@username/trust` or `/a/<author_id>/trust`; old `/trust/people/<id>`
links redirect permanently, and their `?tab=statements` links redirect to the person’s profile.
“Where they stand” opens that profile. The reasons link appears only when an eligible public
list includes a nonblank reason; private Council choices never affect its visibility.
Profiles show a public-lists link (`/@username/lists` or `/a/<author_id>/lists`) only when
the author has a published list. Legacy community
pages redirect to the Trust List for admins and Council setup for other visitors. Historical
snapshots and CSV exports remain available to admins.
`/trust/updates` retains private updates. The former `/trust/requests` page is removed.

The invite step provides a short author-ID referral link (`/council?ref=123`), sharing controls, and optional email
invitations (up to 10 at once and 20 per day, with duplicate recipients suppressed).
Development and test use local mail adapters; they do not send external mail.

Run migrations before starting the release. Consolidation preserves existing picks and
queues resumable `RefreshCouncilWorker` jobs to refresh voting projections. Monitor those
jobs before rollout. Do not roll back the schema after users edit collections without
exporting their choices.

Validate with `mix check`. Start the local review server with `PORT=4006 mix phx.server`.
