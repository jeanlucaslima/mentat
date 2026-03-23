# World Engine v0 — Event Loop

```
                       WORLD STARTS
                            │
                            ▼
                   ┌─────────────────┐
                   │  CLOCK FIRES    │ ◄─────────────┐
                   │  every N ms     │               │
                   └────────┬────────┘               │
                            │ {:tick, N}             │
              ┌─────────────┼─────────────┐          │
              ▼             ▼             ▼          │
         nation A      nation B  ...  nation E       │
              │                                      │
              ▼                                      │
        READ ETS                                     │
              │                                      │
              ▼                                      │
        UPDATE STATE                                 │
              │                                      │
              ▼                                      │
        CHECK TRIGGERS                               │
              │                                      │
              ├── FAMINE? ──► update · cast async ──►│
              ├── COUP?   ──► swap ruleset · cast ──►│
              ├── DEFAULT? ──► downgrade · cast ────►│
              └── REBELLION? ─► lose tile · cast ───►│
              │                                      │
              ▼                                      │
        CALL AGENT (FSM)                             │
              │                                      │
              ├── survival rule                      │
              ├── expansion rule                     │
              ├── consolidation rule                 │
              └── nil (wait)                         │
              │                                      │
              ▼                                      │
        VALIDATE ACTION                              │
              │                                      │
              ├── valid?   ──► update ETS · cast ───►│
              └── invalid? ──► cast rejection ──────►│
              │                                      │
              ▼                                      │
        CAST SNAPSHOT ──────────────────────────────►│
              │                                      │
              └──────────────────────────────────────┘
                         next tick

                                        │
                     all casts go to    │
                                        ▼
              ╔═════════════════════════════════════╗
              ║       PERSISTENCE WORKER            ║
              ║   queues · batches · writes async   ║
              ╚══════════════════╦══════════════════╝
                                 ║
                                 ▼
              ╔═════════════════════════════════════╗
              ║           POSTGRESQL                ║
              ║  nation_snapshots · tile_snapshots  ║
              ║  events · actions                   ║
              ╚══════════════════╦══════════════════╝
                                 ║
                                 ▼
              ╔═════════════════════════════════════╗
              ║        REPLAY INTERFACE             ║
              ║   scrub to tick · query · render    ║
              ╚═════════════════════════════════════╝
```
