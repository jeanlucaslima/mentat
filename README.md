# Mentat

Mentat is an open-source, persistent geopolitical world simulation engine. Five nations occupy a shared map, produce resources, control territory, and respond to political events — continuously, whether or not anyone is watching. Nations are controlled by pluggable agents: rule-based finite state machines today, large language models tomorrow.

## Why this exists

Most AI benchmarks for strategic reasoning use discrete episodes: a game starts, agents act, the game ends, scores are tallied. This works for measuring short-horizon decision-making but tells us nothing about how an LLM behaves over weeks of simulated time — whether it drifts, forgets commitments, overreacts to compounding crises, or develops stable long-term strategies. Mentat provides the infrastructure to study these questions. The world never resets. Every action is logged. Agents can be swapped mid-run. The engine enforces physical and political constraints so agents cannot cheat — they must operate within the rules of their government type, terrain, and resource reality.

## Architecture

The simulation runs on Elixir/OTP. A Clock GenServer ticks at a configurable interval (one tick = one simulated hour). Each tick, five Nation GenServers — one per nation — read the current world state from ETS, run passive event checks (famine, coups, rebellions), call their pluggable agent for a decision, validate the proposed action against engine rules, and write the result back to ETS. A separate Persistence Worker asynchronously batches all state changes, events, and actions into PostgreSQL. A Phoenix LiveView replay interface lets you scrub to any tick and inspect the full world state. Scenario files (map, nations, structures) are loaded once at startup and define the initial conditions.

## Running locally

```bash
# Prerequisites: Elixir 1.18+, PostgreSQL 15+, Node.js 20+

# Clone and setup
git clone https://github.com/jeanlucaslima/mentat.git
cd mentat
mix setup

# Start the dev server
mix phx.server

# Or start with an interactive shell
iex -S mix phx.server

# Run tests
mix test

# Run pre-commit checks (compile, format, test)
mix precommit
```

> **Note:** The simulation engine is under active development. These steps will set up the Phoenix application scaffold. Scenario loading and the tick loop are not yet implemented.

## Project structure

```
lib/mentat/          # Business logic — contexts, schemas, simulation engine
lib/mentat_web/      # Web layer — router, LiveView, components
priv/scenarios/      # Scenario definitions (map, nations, structures as JSON)
config/              # Environment configs
```

## License

Apache License 2.0. See [LICENSE](LICENSE) for details.

Research collaborations are welcome. If you are studying long-horizon LLM behavior, multi-agent coordination, or AI alignment in persistent environments, open an issue or reach out.
