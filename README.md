# hecate-tom-house

**TOM, Traders of Macao.** The player: one purse, one ship, one page.

*This exists so a human can buy pepper at Macao, watch the ship cross to Lisbon,
sell it there, and see the purse move.*

A house is a **pure client**. It advertises nothing on the mesh and nothing ever
calls it, which is exactly why it can be shut down for an entire voyage and be
precisely right when it comes back. It holds **title and coin**. It is never the
custodian of anything: its picture of its own ship and of the cargo in that
ship's hold is a cached view of somebody else's fact, stamped with when it was
taken.

```
        ┌── you ──┐
        │  page   │  http://localhost:8461
        └────┬────┘
    ┌────────┴────────┐
    │  hecate-tom-    │   purse · orders · the last picture of the ship
    │     house       │   an append-only log, synced before anybody is told
    └────────┬────────┘
             │ dials OUT to a macula-station. No inbound port.
   ══════════╪══════════════════════════════════════════════
      ┌──────┴──────┬──────────────┬──────────────┐
      ▼             ▼              ▼              ▼
  harbour A     harbour B        ocean       (nothing calls the house)
```

## The three questions that make a restart work

A house that has been off for a week asks three questions and is right again.
Nothing was queued for it and nothing was replayed at it.

1. **`get_voyage` at the ocean.** The ocean keeps every voyage record forever, so
   this answers an hour later, a day later, and across any number of restarts on
   either side. Without it a house cannot tell a lost ship from one still at sea,
   because both look like `not_here` from every port.
2. **`get_ship` at the ports.** `not_here` is an answer, not an error. When two
   ports both claim the hull, **the higher hop wins** — the custody rule
   verbatim, with no vote, no quorum and no comparison of two machines' clocks.
3. **Re-call any unsettled order under its original key.** The harbour stored its
   receipt under that key and replays it, so the retry moves no goods and the
   purse moves exactly once.

`restart_tests` runs exactly that: buy at Macao, sail, **shut the house down
completely**, move the world on, start it again, and sell at Lisbon.

## What is durable and what is not

| Durable, synced before anybody is told | Volatile, refetched in seconds |
|---|---|
| the purse | prices at both ports |
| every order and how it concluded | the news ticker |
| the last picture of the ship | the last thing that went wrong |

Genesis applies **once**: the configured purse enters the log only when the log
has no record of this house ever having opened. A house that re-seeded its purse
on every boot would mint money by crashing.

## The one distinction everything rests on

| | means | so |
|---|---|---|
| **refused** | the far side answered, and the answer was no | FINAL. Close the order, tell the player, never ask again |
| **unreachable** | the far side did not answer | TRANSIENT. Retry with the SAME key, every five seconds, forever |

Getting it backwards is expensive both ways. Retrying a refusal loops forever
against a harbour that will never change its mind. Treating a timeout as a
refusal abandons an order the harbour may well have executed, and the pepper is
then in the hold with nobody having paid for it.

## THERE IS NO WAREHOUSE

Buying **is** loading. The quay hands the cargo straight into the hull, in one
local act inside the harbour's own process, so the only thing crossing the wire
is a receipt and the only thing this house does with it is move its own number.
There is no separate "load" step because there is nothing to load from: no
procedure in the contract moves goods between a warehouse and a hold, and a
warehouse here would be a room with no doors.

## What is checked here and what is not

The **purse** is checked here, because this house owns the purse. The **hold** is
not, even though the house has a picture of it, because the harbour owns the ship
while it is moored and its picture is the true one. Refusing a legal purchase
against a stale local copy of somebody else's fact is worse than a round trip.

## The page

`http://localhost:8461`. Plain, legible, and it keeps up on its own.

- the purse, and where the ship is in one sentence
- prices and quay stocks at both ports, side by side, with how old each answer is
- what is in the hold, and how much of it is free
- every order, and how each one went, in English rather than in Erlang
- what a port said while you were watching
- **the helm**: price it, buy into the hold, sell out of the hold, cast off for
  the other port, and ask everybody again

The board is rendered on the server and pushed whole over server-sent events. The
**controls sit outside the swapped fragment**, so an update arriving while you are
halfway through typing a quantity cannot eat what you typed. The forms work with
JavaScript switched off: a plain browser posts and is sent back to the page.

**No duration is ever shown for a passage.** The page shows when a ship sailed,
when she is due, and how long is left. It does not show how long a crossing takes
and it must not: that number is the ocean's constant, and recovering it by
subtracting two of the ocean's own timestamps is exactly the leak that putting an
instant on the wire exists to prevent. There is no progress bar for the same
reason.

## Running one

```bash
scripts/play.sh                    # config/local.config, page on :8461
scripts/smoke.sh                   # boots it for real and checks it answers
```

`play.sh` boots with or without a mesh. With no station configured every call
comes back unreachable, the page says so in as many words, and the purse and the
ledger work exactly as they will in a real game. That is the fastest way to look
at the page.

**To play the actual game**, with two harbours and an ocean to trade against,
run the loop from the harbour repository beside this one:

```bash
../hecate-tom-harbour/scripts/play-the-loop.sh     # then open http://localhost:8461
```

It starts a `macula-station`, both harbours, the ocean and this house, and they
find each other over the mesh.

### As a release

```bash
rebar3 as prod release
_build/prod/rel/hecate_tom_house/bin/hecate_tom_house foreground
```

### As a container

```bash
podman build -t hecate-tom-house .
podman run --rm \
    -p 8460:8460 -p 8461:8461 \
    -v tom-house-data:/var/lib/hecate-tom-house \
    -e TOM_REALM_TAG=<64 hex characters> \
    -e TOM_STATION_SEED=quic://station.example:4433 \
    hecate-tom-house
```

⚠ **The volume is not optional.** Without it every restart is a new player with a
fresh thousand coins.

## Configuration

Two things are called "the realm" and they are not the same thing. Confusing them
is the fastest way to a service that answers `/health` and reaches nobody.

| | is | goes |
|---|---|---|
| realm **name** | `<<"io.macula">>` | inside every MRI and every topic |
| realm **tag** | 32 bytes / 64 hex chars | as the second argument to every `macula:call` |

| Setting | Env var in the container | What it is |
|---|---|---|
| `hecate_om.realm` | `TOM_REALM_TAG` | the 32-byte tag. **No default** |
| `hecate_om.station_seeds` | `TOM_STATION_SEED` | the station this house dials. **No default** |
| `hecate_om.health_port` | `TOM_HEALTH_PORT` | `/health`, default 8460 |
| `realm_name` | `TOM_REALM_NAME` | the name inside MRIs, default `io.macula` |
| `player` | `TOM_PLAYER` | who is playing, default `raf` |
| `ship` | `TOM_SHIP` | the one hull, default `santa_clara` |
| `harbours` | `TOM_HARBOURS` | ports, comma separated, default `macao,lisbon` |
| `goods` | `TOM_GOODS` | what the page prices, comma separated |
| `purse` | `TOM_PURSE` | the purse at genesis, applied once |
| `ledger` | `TOM_LEDGER` | the append-only log |
| `web_port` | `TOM_WEB_PORT` | the page, default 8461 |
| `quote_interval_ms` | `TOM_QUOTE_INTERVAL_MS` | how often prices are asked for |
| `locate_interval_ms` | `TOM_LOCATE_INTERVAL_MS` | how often the ship is looked for |

**Names are derived, never written out.** The operator writes `macao`, not
`mri:instance:io.macula/tom/harbour/macao`. Three services have to agree about
what a harbour is called, and the only way two hand-written identifiers cannot
disagree is for neither to be hand-written: every side derives from the same realm
name and the same short name by the same rule.

**A misconfigured house does not boot.** `tom_names:read/1` reports every problem
it finds and the service refuses to start on any of them, because a service that
comes up healthy, answers `/health`, shows an empty page and reaches nobody is
the most expensive kind of working.

**A house with no station reports `degraded`,** which is a 503 on `/health` and an
unhealthy container until a station answers. That is the honest report: it has its
purse, its history and its page, and it cannot do the thing it exists to do.

## What is here

| Module | Is |
|--------|-----|
| `tom_names` | What everything is called on the mesh, derived from one realm name |
| `tom_ledger` | The append-only log, and the repair of a write a crash cut in half |
| `tom_house` | **The aggregate.** Purse, orders and the picture of the ship, as a fold. Pure |
| `tom_wire` | The behaviour, and the refused/unreachable taxonomy everything turns on |
| `tom_wire_macula` | That taxonomy against what the SDK actually delivers |

| Slice | Is |
|-------|-----|
| `keep_house/` | The one process that owns the purse, the log and the book of orders |
| `buy_cargo/` | Price it, write the intent, call, settle. Straight into the hold |
| `sell_cargo/` | The mirror, out of the hold |
| `sail_ship/` | Consign her to the ocean. No key: the ship's own state is the key |
| `find_ship/` | The three questions. **The point of the whole architecture** |
| `settle_orders/` | Drive every order a crash left open to a conclusion |
| `watch_ports/` | The seven facts, for the ticker. Load-bearing for nothing |
| `read_quotes/` | Ask both ports what things cost, over and over |
| `show_house/` | The page, the stream, the acts and the JSON |

## Build

```bash
rebar3 eunit
rebar3 lint
rebar3 dialyzer
scripts/smoke.sh
```

## Two things the wire does that the contract did not say it did

Both were found by running the four services against a real station. Both break
the loop silently rather than loudly, and both are now fixed on the side that
owns the problem.

**A key does not arrive in the shape it was sent.** The contract says every key
on the wire is a binary. That is true of what a sender writes and false of what
a receiver gets. macula encodes a binary key as a CBOR text string, and
`macula_frame:from_wire_envelope/1` then runs `binary_to_existing_atom` over
every one: a key whose name is already in this node's atom table arrives as an
**atom**, one whose name is not arrives as **`{text, Binary}`**. One receipt
carries both — `coin` as an atom beside `{text, <<"price_after">>}` — and which
shape a key takes is a property of **this node** rather than of the message:
loading any module that mentions the atom `coin` changes it, quietly, for every
payload afterwards.

A house that read a receipt raw would find no `<<"coin">>` in it, leave the order
open, and retry it forever against a harbour that had already taken the money.
`tom_wire_accept:payload/1` folds a payload back to binary keys at the two places
one crosses: every reply in `tom_wire_macula:call/3`, and every fact in
`watch_ports`. It mints no atom doing it.

**A refusal's reason does not survive `{error, Binary}`, so it travels as a
reply.** The frozen contract enumerates reason binaries (`hold_full`,
`quay_empty`, `not_here`, `ship_consigned` and the rest) and calls a refusal
`{error, Binary}`. A handler returning that is turned by the SDK into a BOLT#4
error frame with code `0x0F`, the reason is rendered into the frame's `detail`,
and `macula_station_link`'s client end reads only `code` and `name` — **`detail`
is dropped on the floor.** Every refusal in the game arrives as one
indistinguishable `{error, {call_error, 15, unknown_error}}`.

The harbours therefore answer a refusal with a **successful reply carrying the
reason**, which is the one shape the wire keeps whole:

```erlang
{ok, #{<<"refused">> => <<"hold_full">>}}
```

`tom_wire_macula:classify/1` reads that shape ahead of the plain-map clause and
still calls it `refused`, so it is still FINAL and the retry loop is unchanged.
`show_house_page:say/1` has a sentence for each enumerated reason and shows any
it has never heard of verbatim, because the producer owns the content of what it
sends.

The alternative fix was to carry `detail` through to the caller in
`macula_station_link:on_frame/2` — one line, and arguably the better one. It was
not taken here because it changes the published SDK the rest of the fleet runs,
and because the contract change is confined to the two services that speak this
game.

## What is known to be wrong

**1. The brief and the contract disagree about a warehouse.** The brief asks for
"an inventory (goods held ashore)" and a "load" button. The contract says
`THERE IS NO WAREHOUSE` and makes buying a single act that puts cargo straight
into the hold. This is built to the contract: there is no warehouse and no load
button, because no procedure in the contract could move a ton out of one. The
page says so where a player would look for it.

**2. `get_voyage` is assumed to answer about the most recent voyage.** The
contract says the ocean keeps every voyage record forever and that `get_voyage`
takes only a ship MRI, which leaves the second voyage of one hull unaddressed.
This house assumes the latest, and does not depend on the assumption: a ship that
a port is holding is found by `get_ship` whatever the ocean says about an old
crossing, and the ocean's answer is only used when no port has her.

**3. `hecate_om` cannot receive a mesh event.** `hecate_om_capabilities` matches
`{macula_event, Ref, Topic, Payload}`, a four-tuple. The SDK sends
`{macula_event, SubRef, Topic, Payload, Meta}`, five. Every peer capability
announcement therefore falls through to its catch-all and is dropped. It costs
this house nothing, because it looks nothing up, and it is worth fixing where it
lives.

**4. Clock skew is on the page but never on a decision.** `sighted_at` is this
house's clock and `due_at` is the ocean's, and the page shows both. Nothing here
compares two machines' instants to decide anything: sightings are ordered by the
hop, which only a durable acceptance advances.

**5. There is one player and the page assumes it.** `get_ship` currently answers
anybody, so a second house could watch this one's hull. Nothing here relies on
that either way.

## License

Apache-2.0. See [LICENSE](LICENSE).
