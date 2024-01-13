# Specify the Elixir version
FROM elixir:1.14

# Create and set the working directory
RUN mkdir /app
WORKDIR /app

# Install Hex package manager
RUN mix local.hex --force
# Install rebar (Erlang build tool)
RUN mix local.rebar --force

# Set environment to production
ENV MIX_ENV=prod

# Copy your source folder into the image
COPY . .

# Fetch app dependencies and compile
RUN mix deps.get
RUN mix deps.compile

# Compile assets (if using Phoenix with assets)
# This assumes you're using Phoenix; if not, remove these lines
RUN mix assets.deploy

# Compile the app
RUN mix compile

# Run database migrations
CMD ["mix", "ecto.migrate"]

# The command to run when the container starts
CMD ["mix", "phx.server"]
