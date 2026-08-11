# Changelog

All notable changes to `hecate-tom-house` are recorded here.

The format follows [Keep a Changelog](https://keepachangelog.com/en/1.1.0/) and
this project uses [Semantic Versioning](https://semver.org/spec/v2.0.0.html).

## [0.1.0] - 2026-08-11

The first house. A player, a purse, a ship and a page.

### Added

- **`tom_names`** — every MRI, procedure and topic, derived from one realm name
  so that three services cannot disagree about what a harbour is called. Tested
  against the frozen contract's own literal strings.
- **`tom_ledger`** — an append-only log of length-prefixed terms, synced per
  record, with repair of a partial tail left by a crash mid-write.
- **`tom_house`** — the aggregate: purse, orders and the picture of the ship as a
  fold of facts. Pure, and idempotent in every clause, which is what makes the
  retry after a crash safe.
- **`tom_wire` / `tom_wire_macula`** — the refused-versus-unreachable taxonomy the
  whole reliability pattern rests on, mapped onto what the SDK actually delivers.
- **`keep_house`** — the one process owning the purse, the log and the book of
  orders. Genesis applies once and only into a log that has never seen the house
  open.
- **`buy_cargo`, `sell_cargo`, `sail_ship`** — the three acts, each writing its
  intent before it calls and its conclusion after.
- **`find_ship`** — the three questions that let a house be shut down for a whole
  voyage. Two ports claiming one hull is resolved by the higher hop.
- **`settle_orders`** — the sweep that drives an order left open by a crash to a
  conclusion, under its original key, forever.
- **`watch_ports`** — the seven facts, for the ticker, load-bearing for nothing.
- **`read_quotes`** — prices from both ports, naming the goods rather than asking
  for all sixty-seven.
- **`show_house`** — the page, a server-sent-events stream that pushes a rendered
  board, the acts, and the same snapshot as JSON for a shell.
- `scripts/play.sh` to run a house from the checkout, `scripts/smoke.sh` to boot
  one for real and check it answers.
- A `Containerfile` with a data volume that is not optional.

### Known to be wrong

- A refusal's reason does not survive the wire. The SDK turns a handler's
  `{error, Reason}` into a BOLT#4 frame and its client end drops the `detail`
  field, so the house can say THAT a port refused and not WHY. Classification is
  unaffected and the retry loop is safe. See the README.
- The brief asks for a warehouse and a load button; the contract forbids both.
  Built to the contract.

[0.1.0]: https://github.com/hecate-services/hecate-tom-house/releases/tag/v0.1.0
