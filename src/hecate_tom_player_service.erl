%% @doc The hecate_om service contract, and the one place configuration turns
%% into names.
%%
%% THE HOUSE ADVERTISES NOTHING, and `capabilities/0' returning the empty list is
%% the whole point rather than an omission. Nothing on the mesh ever calls a
%% house: it is a pure client, which is exactly why it can be shut down for a
%% voyage and nothing anywhere blocks waiting for it.
%%
%% A MISCONFIGURED HOUSE DOES NOT BOOT. `tom_names:read/1' reports every problem
%% it finds and this refuses to start on any of them. The alternative is a
%% service that comes up healthy, answers /health, shows an empty page and
%% reaches nobody, which is the most expensive kind of working.
%% @end
-module(hecate_tom_player_service).
-behaviour(hecate_om_service).

-export([start/1, stop/1, health/0, capabilities/0, identity_spec/0, info/0]).
-export([configured/0]).

start(_Opts) ->
    hecate_tom_player_sup:start_link(configured()).

stop(_State) ->
    ok.

%% @doc The house is down without its ledger-keeper and degraded without a mesh.
%%
%% Degraded rather than down is the honest report for a house with no pool: it
%% still has its purse, its history and its page, and it will reach the ports the
%% moment the station answers.
health() ->
    standing(erlang:whereis(keep_house), hecate_om:macula_client()).

%% @doc Nothing. Deliberately. See the module doc.
capabilities() ->
    [].

identity_spec() ->
    #{scope     => <<"tom_house">>,
      actions   => [<<"buy_cargo">>, <<"sell_cargo">>, <<"sail_ship">>,
                    <<"read_market">>, <<"find_ship">>],
      resources => [<<"tom/harbour/*">>],
      ttl_days  => 30}.

info() ->
    #{name        => <<"hecate-tom-player">>,
      version     => version(),
      description => <<"TOM, Traders of Macao: the player's house, purse and ship">>}.

%% @doc Everything this house was told about itself, with the names built.
%% Exported so a shell can check a configuration without starting anything.
-spec configured() -> map().
configured() ->
    named(tom_names:read(#{realm_name => env(realm_name),
                           player     => env(player),
                           ship       => env(ship),
                           harbours   => env(harbours),
                           goods      => env(goods)})).

%%% Internal

named({ok, Names}) ->
    #{names              => Names,
      ledger             => env(ledger),
      purse              => float(env(purse)),
      web_port           => env(web_port),
      quote_interval_ms  => env(quote_interval_ms),
      locate_interval_ms => env(locate_interval_ms)};
named({error, Faults}) ->
    error({hecate_tom_player_misconfigured, Faults}).

standing(undefined, _Mesh)     -> {down, no_keeper};
standing(_Pid, {ok, _Pool})    -> ok;
standing(_Pid, {error, Reason}) -> {degraded, {not_on_the_mesh, Reason}}.

env(Key) -> set(application:get_env(hecate_tom_player, Key), Key).

set({ok, Value}, _Key) -> Value;
set(undefined, Key)    -> error({hecate_tom_player_unconfigured, Key}).

version() -> reported(application:get_key(hecate_tom_player, vsn)).

reported({ok, Vsn}) -> list_to_binary(Vsn);
reported(undefined) -> <<"0.0.0">>.
