%% @doc The house itself: a purse, a hull and a book of orders. Pure.
%%
%% This exists so the answer to "how much money have I got" is a fold of things
%% that happened rather than a number somebody assigned. Nothing here reads a
%% clock, opens a socket or spawns a process, so a restart is a replay and a
%% replay is a test.
%%
%% THE HOUSE IS NEVER A CUSTODIAN. It holds title and coin. Its picture of its
%% own ship and of the cargo in that ship's hold is a cached view of somebody
%% else's fact, and it is stamped with when it was taken. That is why a house can
%% be killed at any instant without a ton of pepper being at risk, and it is why
%% `sight/1' hands back the picture with its age attached rather than pretending
%% to be authoritative.
%%
%% KEYS IN THESE FACTS ARE ATOMS, and keys in anything that came off the mesh are
%% binaries. The two never mix in one map. A receipt arriving from a harbour is
%% read at the boundary, in `keep_house', and what enters the log is this
%% module's own vocabulary. The boundary is visible on purpose.
%% @end
-module(tom_house).

-export([empty/0, apply_fact/2, replay/2]).
-export([purse/1, opened/1, hull/1, cargo/1, hold/1, free_hold/1]).
-export([sight/1, orders/1, unsettled/1, order/2, moved/1, cash_book/1]).

-export_type([house/0, fact/0, order/0, standing/0, book/0, entry/0]).

%% Where the hull is, as far as this house has been told.
%%
%% `unknown' is the honest answer at the instant a house first opens and has not
%% asked anybody yet. It is not a failure and it is not `never_sailed', which is
%% the ocean's positive statement that this hull has never been handed to it.
-type standing() :: unknown | moored | consigned | in_passage
                  | made_landfall | was_lost | never_sailed.

-type order() :: #{order      := binary(),
                   kind       := purchase | sale,
                   harbour    := binary(),
                   good       := binary(),
                   quantity   := float(),
                   at         := integer(),
                   state      := ordered | settled | refused,
                   coin       => float(),
                   moved      => float(),
                   reason     => term(),
                   closed_at  => integer()}.

%% One movement of the purse, with the balance it left behind it.
-type entry() :: #{at       := integer(),
                   order    := binary(),
                   kind     := purchase | sale,
                   harbour  := binary(),
                   good     := binary(),
                   tons     := float(),
                   coin     := float(),
                   balance  := float()}.

-type book() :: #{opened_with := float(),
                  entries     := [entry()],
                  closing     := float()}.

-type house() :: #{opened      := boolean(),
                   purse       := float(),
                   opened_with := float(),
                   ship        := binary() | undefined,
                   hull        := map() | undefined,
                   standing    := standing(),
                   where       := binary() | undefined,
                   bound_for   := binary() | undefined,
                   sailed_at   := integer() | undefined,
                   due_at      := integer() | undefined,
                   cause       := binary() | undefined,
                   sighted_at  := integer() | undefined,
                   orders      := #{binary() => order()}}.

-type fact() :: {atom(), map()}.

%% @doc A house that has never had anything happen to it.
-spec empty() -> house().
empty() ->
    #{opened      => false,
      purse       => 0.0,
      opened_with => 0.0,
      ship        => undefined,
      hull        => undefined,
      standing    => unknown,
      where       => undefined,
      bound_for   => undefined,
      sailed_at   => undefined,
      due_at      => undefined,
      cause       => undefined,
      sighted_at  => undefined,
      orders      => #{}}.

%% @doc Fold a history into a house.
-spec replay([fact()], house()) -> house().
replay(Facts, House) -> lists:foldl(fun apply_fact/2, House, Facts).

%% @doc One fact, applied.
%%
%% EVERY CLAUSE IS IDEMPOTENT. Settling an order that is already settled changes
%% nothing, and so does settling one this house never placed. That is not
%% defensive padding: the reliability pattern re-calls an outstanding order after
%% a crash, and the difference between "no effect" and "subtract the money
%% twice" is the whole reason the pattern is safe.
-spec apply_fact(fact(), house()) -> house().
apply_fact({house_opened_v1, F}, #{opened := false} = H) ->
    H#{opened      => true,
       purse       => maps:get(purse, F),
       opened_with => maps:get(purse, F),
       ship        => maps:get(ship, F)};
apply_fact({house_opened_v1, _F}, H) ->
    H;

apply_fact({purchase_ordered_v1, F}, H) ->
    placed(purchase, F, H);
apply_fact({sale_ordered_v1, F}, H) ->
    placed(sale, F, H);

apply_fact({purchase_settled_v1, F}, H) ->
    settled(purchase, maps:get(filled, F), F, H);
apply_fact({sale_settled_v1, F}, H) ->
    settled(sale, maps:get(discharged, F), F, H);

apply_fact({purchase_refused_v1, F}, H) ->
    refused(F, H);
apply_fact({sale_refused_v1, F}, H) ->
    refused(F, H);

apply_fact({ship_sighted_v1, F}, H) ->
    sighted(fresher(F, H), F, H);

apply_fact(_Unknown, H) ->
    H.

%%% Questions

-spec purse(house()) -> float().
purse(#{purse := P}) -> P.

-spec opened(house()) -> boolean().
opened(#{opened := O}) -> O.

%% @doc The last ship map seen, exactly as its custodian sent it.
-spec hull(house()) -> map() | undefined.
hull(#{hull := Hull}) -> Hull.

%% @doc What is in the hold: good MRI to tons. Empty when there is no picture.
-spec cargo(house()) -> #{binary() => number()}.
cargo(#{hull := undefined}) -> #{};
cargo(#{hull := Hull})      -> maps:get(<<"cargo">>, Hull, #{}).

%% @doc The hull's capacity in tons, or 0.0 when nothing has been seen yet.
-spec hold(house()) -> number().
hold(#{hull := undefined}) -> 0.0;
hold(#{hull := Hull})      -> maps:get(<<"hold">>, Hull, 0.0).

%% @doc Capacity minus what is aboard.
-spec free_hold(house()) -> number().
free_hold(House) ->
    hold(House) - lists:sum(maps:values(cargo(House))).

%% @doc Where the hull is, with the age of the answer attached.
%%
%% `sighted_at' is when the picture was taken by this house's clock. A page shows
%% it because a picture without an age invites a player to believe it.
-spec sight(house()) -> map().
sight(#{standing := S, where := W, bound_for := B, sailed_at := SA,
        due_at := D, cause := C, sighted_at := At, ship := Ship}) ->
    #{standing => S, where => W, bound_for => B, sailed_at => SA,
      due_at => D, cause => C, sighted_at => At, ship => Ship}.

%% @doc Every order this house has ever placed, newest first.
-spec orders(house()) -> [order()].
orders(#{orders := O}) ->
    lists:sort(fun(#{at := A}, #{at := B}) -> A >= B end, maps:values(O)).

%% @doc The orders that were placed and never concluded.
%%
%% THIS IS THE LIST A HOUSE RESUMES FROM. Each one is re-called with its original
%% key until the harbour says something definite, which it will, because the
%% harbour stores the receipt under that key and replays it.
-spec unsettled(house()) -> [order()].
unsettled(House) -> [O || #{state := ordered} = O <- orders(House)].

-spec order(house(), binary()) -> {ok, order()} | error.
order(#{orders := O}, Key) -> maps:find(Key, O).

%% @doc The purse as an account: what the house opened with, every movement
%% since, and the balance each one left behind it.
%%
%% THIS FOLDS FORWARD AND NEVER SUBTRACTS FROM THE PURSE. A book whose closing
%% balance is derived from the purse cannot disagree with the purse, and a book
%% that cannot disagree is decoration. This one starts from what the house opened
%% with and adds up, so `closing' and `purse/1' are the same question answered by
%% two routes, and if they ever differ that is worth knowing.
%%
%% ORDERED BY WHEN THE MONEY MOVED, which is when a port settled, not when the
%% order was placed. `orders/1' is newest first because it is a log somebody
%% scans; this is oldest first because a running balance only means anything read
%% downwards.
%%
%% ONLY A SETTLEMENT MOVES MONEY. An order still open has committed nothing and a
%% refusal cost nothing, so neither appears here. Both are in `orders/1', which is
%% where a player looks for what became of an order rather than of a coin.
-spec cash_book(house()) -> book().
cash_book(#{opened_with := Opened} = House) ->
    Settled = lists:sort(fun(#{closed_at := A}, #{closed_at := B}) -> A =< B end,
                         [O || #{state := settled} = O <- orders(House)]),
    {Entries, Closing} = lists:mapfoldl(fun entry/2, Opened, Settled),
    #{opened_with => Opened, entries => Entries, closing => Closing}.

%% @doc How many tons an order actually moved.
%%
%% WHAT WAS ASKED FOR AND WHAT MOVED ARE NOT THE SAME NUMBER, and the difference
%% is visible in normal play rather than in an edge case: a quay holds what it
%% holds, so an order for five tons at a shallow port fills two and a half, and
%% the receipt says `filled' or `discharged' rather than echoing the request.
%% `quantity' stays what was ordered, because that is what a retry re-sends
%% under the same key; this is what a player is shown.
-spec moved(order()) -> float().
moved(#{state := settled} = Order) -> maps:get(moved, Order, 0.0);
moved(#{quantity := Quantity})     -> Quantity.

%%% Internal

entry(Order, Running) ->
    Coin    = maps:get(coin, Order),
    Balance = Running + direction(maps:get(kind, Order)) * Coin,
    {#{at      => maps:get(closed_at, Order),
       order   => maps:get(order, Order),
       kind    => maps:get(kind, Order),
       harbour => maps:get(harbour, Order),
       good    => maps:get(good, Order),
       tons    => moved(Order),
       coin    => Coin,
       balance => Balance},
     Balance}.

placed(Kind, F, #{orders := Orders} = H) ->
    Key = maps:get(order, F),
    minted(maps:is_key(Key, Orders), Kind, Key, F, H).

%% Placing an order twice under one key is the same order. The key is minted by
%% this house and is unique per order, so a repeat is a replay.
minted(true, _Kind, _Key, _F, H) ->
    H;
minted(false, Kind, Key, F, #{orders := Orders} = H) ->
    H#{orders => Orders#{Key => #{order    => Key,
                                  kind     => Kind,
                                  harbour  => maps:get(harbour, F),
                                  good     => maps:get(good, F),
                                  quantity => maps:get(quantity, F),
                                  at       => maps:get(at, F),
                                  state    => ordered}}}.

%% WHICH WAY A KIND MOVES THE PURSE, in the one place that knows. A cash book
%% has to answer the same question the fold does, and a sign rule written down
%% twice is a sign rule that will disagree with itself the day a third kind of
%% movement arrives. Tax, wages and a toll are all clauses here and nothing else
%% changes.
-spec direction(purchase | sale) -> -1 | 1.
direction(purchase) -> -1;
direction(sale)     -> +1.

settled(Kind, Moved, F, H) ->
    Coin = maps:get(coin, F),
    concluded(open_order(F, H), settled, #{coin => Coin, moved => Moved},
              direction(Kind) * Coin, F, H).

refused(F, H) ->
    concluded(open_order(F, H), refused, #{reason => maps:get(reason, F)},
              0.0, F, H).

open_order(F, #{orders := Orders}) ->
    maps:get(maps:get(order, F), Orders, closed).

%% An order that is not open absorbs nothing. That covers the repeat settlement,
%% the settlement of an order this house never placed, and the settlement that
%% arrives after a refusal.
concluded(closed, _State, _Extra, _Coin, _F, H) ->
    H;
concluded(#{state := ordered} = Order, State, Extra, Coin,
          F, #{orders := Orders, purse := Purse} = H) ->
    Key  = maps:get(order, F),
    Done = maps:merge(Order#{state => State, closed_at => maps:get(at, F)}, Extra),
    H#{orders => Orders#{Key => Done}, purse => Purse + Coin};
concluded(_Order, _State, _Extra, _Coin, _F, H) ->
    H.

%% A sighting that carries a hop LOWER than the one already recorded is older
%% news than what is here, whoever it came from. Hop is the custody counter and
%% only a durable acceptance advances it, so it orders sightings without
%% comparing two machines' clocks. Equal hops pass: mooring and consignment
%% happen at the same hop, and consignment is a real change.
fresher(F, H) -> not behind(hop_of(maps:get(hull, F, undefined)), hop_of(hull(H))).

behind(New, Old) when is_integer(New), is_integer(Old) -> New < Old;
behind(_New, _Old)                                     -> false.

hop_of(Hull) when is_map(Hull) -> maps:get(<<"hop">>, Hull, undefined);
hop_of(_)                      -> undefined.

%% A sight that does not mention the hull leaves it alone, which is right for a
%% ship at sea: the ocean reports where she is, not what is stacked in her hold.
%%
%% It is wrong exactly once. A ship on the bottom has no hold, and whatever she
%% was carrying went down with her, so a `was_lost' sight that forgot to say so
%% used to leave the player looking at a manifest for cargo on the sea floor,
%% written to the ledger and replayed for ever after.
%%
%% The rule lives here rather than in the sight because it is the house's to
%% keep. A future sight can forget; an aggregate cannot.
afloat(was_lost, _Hull) -> undefined;
afloat(_Standing, Hull) -> Hull.

sighted(false, _F, H) ->
    H;
sighted(true, F, H) ->
    H#{hull       => afloat(maps:get(standing, F),
                            maps:get(hull, F, hull(H))),
       standing   => maps:get(standing, F),
       where      => maps:get(where, F, undefined),
       bound_for  => maps:get(bound_for, F, undefined),
       sailed_at  => maps:get(sailed_at, F, undefined),
       due_at     => maps:get(due_at, F, undefined),
       cause      => maps:get(cause, F, undefined),
       sighted_at => maps:get(at, F)}.
