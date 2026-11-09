# YouCongress

[YouCongress.org](https://youcongress.org) is a non-profit, open-source platform for sourced quotes, policy proposals, and claims, with an initial focus on AI governance. Its participation layer supports direct voting and optional delegation through a private Council.

## Sourced knowledge

Records preserve the quotation, author, source, date, and links to relevant proposals or claims. Each link has a stance (For, Abstain/unclear, or Against), with separate verification histories for source fidelity, relevance, and stance. Automated verification is not independent human validation; quote and vote counts are not measures of truth or representative public opinion.

- [Download the CSV dataset](https://youcongress.org/dataset.csv).
- [Use the public MCP endpoint](https://youcongress.org/mcp) with the [tool documentation](https://youcongress.org/mcp-tools). Scoped API keys enable authenticated contributions.
- See the [agent workflow guide](agents-workflows/README.md) for ingestion and verification details.

## My Council

At `/council`, choose people lists for particular halls or for All statements. Lists are checked in your saved order, skipping halls that do not match the proposal or claim. The first applicable list with more For than Against, or more Against than For, decides your delegated vote. Abstentions and missing positions do not count; ties move to the next list. Your direct vote always takes priority, and delegation does not follow chains.

People lists can be private or public. You can use your own lists or follow someone else's public list; membership changes refresh dependent Council votes. Council assignments stay private even when the selected list is public. Public lists have shareable URLs such as `/@username/lists/<slug>`. Trust 30 rankings remain admin-only while participation grows.

## Run locally

Install Elixir/Erlang and PostgreSQL, then:

```bash
mix deps.get
mix ecto.setup
mix phx.server
```

Open [localhost:4000](http://localhost:4000). Setup creates sample data and a development admin account: `admin@youcongress.org` / `admin:1234`.

For port 4006, run `PORT=4006 mix phx.server`. Run migrations before starting a release; Council data migrations may queue background vote refreshes.

## Contribute

- Run `mix check` for formatting, compilation, assets, linting, tests, and security scanning.
- Run `mix precommit` before committing; it also audits dependencies and checks test coverage. `mix ci` runs the same checks. These commands use the test database; dependency auditing needs network access and Hex 2.5.1 or newer.
- Pick an [issue](https://github.com/youcongress/youcongress/issues), or email hector@youcongress.org to help validate quotes.

## License and credits

Code: [MIT](LICENSE). Structured annotations and metadata: [CC BY 4.0](https://creativecommons.org/licenses/by/4.0/), with attribution to YouCongress. Third-party quotations and bios retain their original rights and source links.

Built by [Hector Perez Arenas](https://www.linkedin.com/in/hectorperezarenas/). Thanks to [AppSignal](https://www.appsignal.com) and [Rocket Validator](https://rocketvalidator.com).
