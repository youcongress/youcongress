# Welcome to YouCongress.org

[YouCongress.org](https://youcongress.org) is a non-profit, open-source platform for building source-grounded knowledge bases around hard public questions. It combines a verifiable quotes and claims database with a liquid democracy participation layer so expert and citizen preferences stay visible.

The sourced quotes power structured policy statements, community votes, and optional delegation. Citizens can search topics, inspect sources, vote directly, pick delegates (including public figures whose stances we infer from their sourced quotes), or help validate new quotes to improve the dataset. The first large focus is AI governance, but the workflow is intended to generalize to other epistemic case studies.

## Agent workflows and verification

YouCongress has repository-backed and scheduled coding-agent workflows that converge on the same quote, statement, and verification records. Both use separate passes for discovery, attribution, statement linking, stance inference, source fidelity, relevance, and stance checks; automated agreement is not human validation. Read the [agent workflow guide](agents-workflows/README.md) for the full process, its limits, manual review and profile-claiming options, and reusable skills for [adding topic quotes](agents-workflows/skills/youcongress-topic-quotes/SKILL.md) and [verifying quotes](agents-workflows/skills/youcongress-verify-quotes/SKILL.md).

# How to start

Install dependencies:

```bash
mix deps.get
```

Create the database, the user `admin@youcongress.org` with password `admin:1234` and other sample data (authors, quotes):

```bash
mix ecto.setup
```

Run the server:

```bash
mix phx.server
```

Open [http://localhost:4000](http://localhost:4000) in your browser.


# How to contribute
Welcome to YouCongress! Feel free to:
- Reach hector@youcongress.org if you'd like to help validating quotes found by our AI agents.
- [Take any unassigned issue](https://github.com/youcongress/youcongress/issues)

# Acknowledgments

We appreciate the following companies who provide their services kindly for free:

- [AppSignal](https://www.appsignal.com) for application monitoring
- [Rocket Validator](https://rocketvalidator.com) for HTML and accessibility checks.
