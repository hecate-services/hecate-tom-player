# Changelog

All notable changes to `hecate-tom-player` are recorded here.

The format follows [Keep a Changelog](https://keepachangelog.com/en/1.1.0/) and
this project uses [Semantic Versioning](https://semver.org/spec/v2.0.0.html).

## [Unreleased]

### Added

- **The cash book.** `tom_house:cash_book/1` reads the purse as an account: what
  the house opened with, every movement since, and the balance each one left
  behind. On the page as a panel, in `/view` whole, and in
  `scripts/cash-book.sh` for a ledger on a disk.
- **`scripts/cash-book.sh`** — replays a ledger and prints the account. Opens the
  file for reading only, so it can be pointed at a house that is up and trading.

### Changed

- **`tom_house:direction/1`** is now the one place that knows which way a kind of
  movement takes the purse. It was a sign in two clauses of the fold, and a cash
  book has to answer the same question; a sign rule written twice disagrees with
  itself the day a third kind of movement arrives.
- **`opened_with`** is kept on the aggregate. The cash book folds forward from it
  rather than subtracting from the purse, so its closing balance and `purse/1`
  are two routes to one answer instead of one number shown twice.

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

[0.1.0]: https://github.com/hecate-services/hecate-tom-player/releases/tag/v0.1.0
