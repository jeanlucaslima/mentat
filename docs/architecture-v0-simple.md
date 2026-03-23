# World Engine v0 — Architecture Overview

```
╔═════════════════════════════════════════════════════╗
║                  SCENARIO FILES                     ║
║         map.json · nations.json · structures.json   ║
╚═════════════════════════╦═══════════════════════════╝
                          ║ loaded once at startup
╔═════════════════════════╩═══════════════════════════╗
║                   WORLD INIT                        ║
║      parse files · write ETS · start processes      ║
╚═════════════════════════╦═══════════════════════════╝
                          ║
╔═════════════════════════╩═══════════════════════════╗
║               CLOCK GENSERVER                       ║
║         fires every N ms · 1 tick = 1 hour          ║
╚═════════════════════════╦═══════════════════════════╝
                          ║ {:tick, N} to all nations
╔═════════════════════════╩═══════════════════════════╗
║            NATION GENSERVER ×5                      ║
║      reads ETS · updates state · fires events       ║
║                                                     ║
║   ┌─────────────────────────────────────────────┐   ║
║   │         NATION AGENT (FSM)                  │   ║
║   │   snapshot in · action out · swappable      │   ║
║   └─────────────────────────────────────────────┘   ║
║                                                     ║
║      validates action · executes · casts async      ║
╚══════════════╦══════════════════════════════════════╝
               ║
     ┌─────────╩──────────┐
     ▼                    ▼
╔══════════════╗  ╔════════════════════════════════════╗
║  ETS TABLES  ║  ║      PERSISTENCE WORKER            ║
║  ground truth║  ║  async · batches · never blocks    ║
╚══════════════╝  ╚═════════════════╦══════════════════╝
                                    ║
                                    ▼
                  ╔═════════════════════════════════════╗
                  ║           POSTGRESQL                ║
                  ║  snapshots · events · actions · log ║
                  ╚═════════════════╦═══════════════════╝
                                    ║
                                    ▼
╔═════════════════════════════════════════════════════╗
║              REPLAY INTERFACE                       ║
║   Phoenix LiveView · scrubber · SVG map · feeds     ║
╚═════════════════════════════════════════════════════╝
```
