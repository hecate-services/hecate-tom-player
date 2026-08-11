%% @doc Find out where the hull actually is, by asking.
%%
%% THIS IS THE POINT OF THE WHOLE ARCHITECTURE. A house can be shut down for an
%% entire voyage and know exactly where its ship is within one pass of this
%% module, because nothing it needs was ever pushed at it. Three reads, each to
%% the service that owns the answer:
%%
%%   1. the ocean, which keeps every voyage record forever, so it answers an
%%      hour later, a day later, and across any number of restarts on either
%%      side. Without this a house cannot tell a lost ship from one still at
%%      sea, because both look like `not_here' from every port.
%%   2. the ports, each of which answers for a ship it holds. `not_here' is an
%%      answer, not an error.
%%   3. whoever is holding it, for the ship map, which carries the cargo that
%%      survived the passage.
%%
%% WHEN TWO PORTS BOTH CLAIM THE SHIP, THE HIGHER HOP WINS. That is the custody
%% rule verbatim: custody is held by whoever recorded taking the ship at the
%% highest hop, the counter is monotone, and only a durable acceptance advances
%% it. No vote, no quorum, no arbiter, and nothing here compares two machines'
%% clocks to decide anything.
%%
%% A FACT NEVER MOVES THE PICTURE, it only triggers a pass. That keeps the
%% house's own record ordered by one process asking in one order, instead of by
%% whichever of seven publications happened to arrive first.
%% @end
-module(find_ship).
-behaviour(gen_server).

-export([start_link/1, look/0, look_around/1]).
-export([init/1, handle_call/3, handle_cast/2, handle_info/2, terminate/2]).

%% A burst of facts arriving together is one thing happening, not seven. Passes
%% closer together than this are folded into one that runs shortly.
-define(COALESCE_MS, 1_000).

%% @doc Where a pass ended up.
-type outcome() :: {sight, map()} | {no_news, term()}.

-spec start_link(map()) -> {ok, pid()} | {error, term()}.
start_link(Config) ->
    gen_server:start_link({local, ?MODULE}, ?MODULE, Config, []).

%% @doc Ask again, soon. Idempotent and safe to shout at.
-spec look() -> ok.
look() -> gen_server:cast(?MODULE, look).

%% @doc One pass, as a function of the names and whatever the mesh says.
%% Exported because this is the behaviour worth testing and it needs no process.
-spec look_around(tom_names:names()) -> outcome().
look_around(Names) ->
    afloat(ask(maps:get(ocean, Names), <<"get_voyage">>, ship_of(Names)), Names).

%%% gen_server

init(Config) ->
    self() ! look,
    {ok, #{names    => maps:get(names, Config),
           interval => maps:get(locate_interval_ms, Config),
           timer    => undefined,
           last     => 0}}.

handle_call(_Msg, _From, S) -> {reply, {error, unknown_call}, S}.

handle_cast(look, S) -> {noreply, soon(S)};
handle_cast(_Msg, S)  -> {noreply, S}.

handle_info(look, S) -> {noreply, run(S)};
handle_info(_Msg, S) -> {noreply, S}.

terminate(_Reason, _S) -> ok.

%%% Internal

%% A poke that lands right after a pass waits a moment rather than starting a
%% second one, so seven facts about one arrival cost one round of questions.
soon(#{last := Last} = S) ->
    due(erlang:system_time(millisecond) - Last < ?COALESCE_MS, S).

due(true, S)  -> armed(?COALESCE_MS, S);
due(false, S) -> run(S).

run(#{names := Names, interval := Interval} = S) ->
    ok = acted(look_around(Names)),
    armed(Interval, S#{last => erlang:system_time(millisecond)}).

armed(After, #{timer := Timer} = S) ->
    _ = cancelled(Timer),
    S#{timer => erlang:send_after(After, self(), look)}.

cancelled(undefined) -> ok;
cancelled(Timer)     -> erlang:cancel_timer(Timer).

acted({sight, Sight})   -> ok = keep_house:sight(Sight),
                           keep_house:note_all_well(find_ship);
acted({no_news, Why})   -> keep_house:note_trouble(find_ship, Why).

ship_of(Names) -> #{<<"ship">> => maps:get(ship, Names)}.

ask(Target, Procedure, Payload) ->
    tom_wire:call(tom_names:procedure(Target, Procedure), Payload, read).

%% At sea the ocean is the custodian and no port holds anything, so there is
%% nothing to ask a port about. The reply carries `due_at', an absolute instant,
%% and never a duration: the length of a passage is the ocean's constant and this
%% house has no business deriving it.
afloat({ok, #{<<"state">> := <<"in_passage">>} = Voyage}, Names) ->
    {sight, #{standing  => in_passage,
              where     => maps:get(ocean, Names),
              bound_for => maps:get(<<"bound_for">>, Voyage, undefined),
              sailed_at => maps:get(<<"sailed_at">>, Voyage, undefined),
              due_at    => maps:get(<<"due_at">>, Voyage, undefined),
              at        => erlang:system_time(millisecond)}};
afloat(Voyage, Names) ->
    ashore(Voyage, custodians(Names), Names).

ashore(Voyage, [], Names)      -> hearsay(Voyage, Names);
ashore(_Voyage, Holders, _Nms) -> {sight, alongside(highest(Holders))}.

%% Every port that says it is holding the ship, with the hop it holds it at.
custodians(Names) ->
    [Held
     || {_Local, Harbour} <- maps:get(harbours, Names),
        Held <- [holding(Harbour, ask(Harbour, <<"get_ship">>, ship_of(Names)))],
        Held =/= none].

holding(Harbour, {ok, #{<<"state">> := <<"moored">>} = Reply}) ->
    {Harbour, moored, hull_of(Reply), undefined};
holding(Harbour, {ok, #{<<"state">> := <<"consigned">>} = Reply}) ->
    {Harbour, consigned, hull_of(Reply), maps:get(<<"bound_for">>, Reply, undefined)};
holding(_Harbour, _Anything_else) ->
    none.

hull_of(Reply) -> a_hull(maps:get(<<"ship">>, Reply, undefined)).

a_hull(Hull) when is_map(Hull) -> Hull;
a_hull(_NotAShip)              -> undefined.

%% The custody rule in one line.
highest(Holders) ->
    hd(lists:sort(fun(A, B) -> hop(A) >= hop(B) end, Holders)).

hop({_Harbour, _State, Hull, _BoundFor}) when is_map(Hull) ->
    maps:get(<<"hop">>, Hull, -1);
hop(_Held) ->
    -1.

alongside({Harbour, Standing, Hull, BoundFor}) ->
    #{standing  => Standing,
      where     => Harbour,
      hull      => Hull,
      bound_for => BoundFor,
      at        => erlang:system_time(millisecond)}.

%% Nobody is holding the hull, so the only thing left to go on is what the ocean
%% said. Landfall is TRUE from the moment the ocean writes it, even while the
%% destination is down and the knocking goes on for an hour, so `made_landfall'
%% with nobody alongside is a real state of the world and not a contradiction.
hearsay({ok, #{<<"state">> := <<"was_lost">>} = Voyage}, _Names) ->
    {sight, #{standing  => was_lost,
              where     => undefined,
              bound_for => maps:get(<<"bound_for">>, Voyage, undefined),
              sailed_at => maps:get(<<"sailed_at">>, Voyage, undefined),
              cause     => maps:get(<<"cause">>, Voyage, undefined),
              at        => erlang:system_time(millisecond)}};
hearsay({ok, #{<<"state">> := <<"made_landfall">>} = Voyage}, Names) ->
    {sight, #{standing  => made_landfall,
              where     => maps:get(ocean, Names),
              bound_for => maps:get(<<"bound_for">>, Voyage, undefined),
              sailed_at => maps:get(<<"sailed_at">>, Voyage, undefined),
              at        => erlang:system_time(millisecond)}};
hearsay({ok, #{<<"state">> := <<"never_sailed">>}}, _Names) ->
    {sight, #{standing  => never_sailed,
              where     => undefined,
              at        => erlang:system_time(millisecond)}};
hearsay({ok, Unrecognised}, _Names) ->
    {no_news, {ocean_said_something_new, Unrecognised}};
hearsay({refused, Why}, _Names) ->
    {no_news, {ocean_refused, Why}};
hearsay({unreachable, Why}, _Names) ->
    {no_news, {nobody_answered, Why}}.
