%% @doc Listen to the six facts the ports publish.
%%
%% NOTHING HERE IS LOAD-BEARING, and that is the design rather than a weakness.
%% A missed fact costs a line in the ticker, never a coin and never a ton.
%% Everything that has to be true is established by a call with a receipt, or
%% read back later from the service that owns it. That is exactly why this house
%% can miss ninety seconds of publications, or a week of them, and still be
%% precisely right when it comes back.
%%
%% So a fact does two harmless things: it goes in the ticker so a player watches
%% a voyage happen, and it pokes `find_ship' to go and ask. The picture itself is
%% only ever written by a completed round of questions, which keeps the house's
%% own record ordered by one process asking in one order rather than by whichever
%% of seven publications arrived first.
%%
%% NO IDENTIFIER IS IN A TOPIC. The harbour, the ship and the good are in the
%% payload, which is what lets this subscribe to seven topics rather than seven
%% times the number of ports.
%% @end
-module(watch_ports).
-behaviour(gen_server).

-export([start_link/1, ours/2]).
-export([init/1, handle_call/3, handle_cast/2, handle_info/2, terminate/2]).

%% A subscription that will not bind yet is not an emergency. The mesh pool
%% attaches a few seconds after boot and nothing is lost in the meantime.
-define(REBIND_MS, 5_000).

-spec start_link(map()) -> {ok, pid()} | {error, term()}.
start_link(Config) ->
    gen_server:start_link({local, ?MODULE}, ?MODULE, Config, []).

%% @doc Whether a publication is about this house's ship.
%%
%% `ship_moored_v1' carries the whole ship map where the others carry its
%% identifier, because the port that just took custody has the map and a port
%% announcing a departure does not. The producer owns the content of what it
%% publishes; the consumer accepts it and reads both shapes.
-spec ours(map(), binary()) -> boolean().
ours(Payload, Ship) -> mine(maps:get(<<"ship">>, Payload, undefined), Ship).

%%% gen_server

init(Config) ->
    Names = maps:get(names, Config),
    self() ! bind,
    {ok, #{names => Names,
           ship  => maps:get(ship, Names),
           bound => #{},
           want  => maps:get(facts, Names)}}.

handle_call(_Msg, _From, S) -> {reply, {error, unknown_call}, S}.

handle_cast(_Msg, S) -> {noreply, S}.

handle_info(bind, S) ->
    {noreply, rebound(bind_all(S))};

%% A fact arrives through the same codec a call does, so its keys are atoms or
%% {text, Binary} rather than the binaries the publisher wrote. Reading one raw
%% makes `ours/2' answer false for every publication, and the ticker stays empty
%% while the ship visibly sails.
handle_info({macula_event, Ref, _Topic, Payload, _Meta}, S) ->
    {noreply, heard(named(Ref, S), tom_wire_accept:payload(Payload), S)};

handle_info({macula_event_gone, Ref, _Reason}, #{bound := Bound} = S) ->
    %% The pool dropped the subscription. Put the topic back on the wanted list
    %% and bind it again; the alternative is a house that goes quiet for good
    %% after one reconnect.
    {noreply, rebound(unbound(Ref, Bound, S))};

handle_info(_Msg, S) ->
    {noreply, S}.

terminate(_Reason, _S) -> ok.

%%% Internal

bind_all(#{want := Want, bound := Bound} = S) ->
    Results = [{Fact, Topic, tom_wire:subscribe(Topic, self())} || {Fact, Topic} <- Want],
    S#{bound => maps:merge(Bound, maps:from_list(
                                    [{Ref, Fact} || {Fact, _T, {ok, Ref}} <- Results])),
       want  => [{Fact, Topic} || {Fact, Topic, {error, _}} <- Results]}.

%% Only arm a retry while something is still unbound, so a fully subscribed house
%% is not waking up every five seconds for the rest of the game.
rebound(#{want := []} = S) ->
    S;
rebound(S) ->
    _ = erlang:send_after(?REBIND_MS, self(), bind),
    S.

unbound(Ref, Bound, #{want := Want, names := Names} = S) ->
    Lost = maps:get(Ref, Bound, undefined),
    S#{bound => maps:remove(Ref, Bound),
       want  => Want ++ [{F, T} || {F, T} <- maps:get(facts, Names), F =:= Lost]}.

named(Ref, #{bound := Bound}) -> maps:get(Ref, Bound, undefined).

heard(undefined, _Payload, S) ->
    S;
heard(Fact, Payload, #{ship := Ship} = S) ->
    minded(ours(Payload, Ship), Fact, Payload),
    S.

%% Somebody else's ship arriving at somebody else's port is none of this house's
%% business and does not belong in this player's ticker.
minded(false, _Fact, _Payload) ->
    ok;
minded(true, Fact, Payload) ->
    ok = keep_house:note_news(Fact, Payload),
    ok = find_ship:look().

mine(MRI, Ship) when is_binary(MRI) ->
    MRI =:= Ship;
mine(Hull, Ship) when is_map(Hull) ->
    maps:get(<<"ship">>, Hull, undefined) =:= Ship;
mine(_Anything_else, _Ship) ->
    false.
