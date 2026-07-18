# YouCongress

[YouCongress.org](https://youcongress.org) is a non-profit, open-source, open-data platform for building source-grounded knowledge bases around hard public questions. It has two connected but distinct layers:

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

- Email hector@youcongress.org if you would like to help validate quotes found by AI agents.
- Take an [unassigned issue](https://github.com/youcongress/youcongress/issues).

## Acknowledgments

- [AppSignal](https://www.appsignal.com) for application monitoring.
- [Rocket Validator](https://rocketvalidator.com) for HTML and accessibility checks.
