# YouCongress

[YouCongress.org](https://youcongress.org) aims to make public preferences on policy questions transparent, structured, and backed by verifiable sources.

The goal is to make it easier for policymakers and journalists to understand what experts and citizens actually want, in a rigorous and non-partisan way.

You can vote directly or choose trusted voices to vote on your behalf, and every poll is enriched with verifiable, sourced quotes so positions are clear and accountable.

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
- [Take any unassigned issue](https://github.com/youcongress/youcongress/issues)
- Propose new features or documentation, refactor existent code, etc.

# Acknowledgments
This project uses [AppSignal](https://www.appsignal.com), which generously provides their services for free. We appreciate their support and trust in our project, helping us monitor YouCongress, maintain quality, and improve continuously.
