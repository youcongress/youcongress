# Welcome to YouCongress.org

[YouCongress.org](https://youcongress.org) is a non-profit, open-source platform that combines a verifiable quotes database with a liquid democracy participation layer focused on AI governance. We gather what leaders, researchers, technologists, and citizens actually said about AI policy.

The sourced quotes power structured policy statements, community votes, and optional delegation so collective preferences stay visible and legible. Citizens can search AI governance topics, vote directly, pick delegates (including public figures whose stances we infer from their sourced quotes), or help validate new quotes to improve the dataset. The result is a decision-support tool that helps people coordinate.

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
