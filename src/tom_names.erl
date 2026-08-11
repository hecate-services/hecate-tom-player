%% @doc What this house calls itself, the ports, the ocean and the goods.
%%
%% Two realms exist and they are not the same thing. The realm NAME is a binary
%% like `<<"io.macula">>' and it goes INSIDE every MRI and every topic. The realm
%% TAG is thirty-two bytes and goes as the second argument to macula:publish and
%% macula:call. This module only ever handles the name. The tag comes from
%% hecate_om_identity and is nobody's business here.
%%
%% NAMES ARE DERIVED, NOT CONFIGURED. The operator writes `macao', not
%% `mri:instance:io.macula/tom/harbour/macao'. Three services have to agree about
%% what a harbour is called, and the only way two hand-written MRIs cannot
%% disagree is for neither to be hand-written: both sides derive from the same
%% realm name and the same short name, by the same rule, which is the rule below.
%%
%% Nothing here mints an atom from anything a stranger sent. Atoms are not
%% garbage collected, so binary_to_atom on an identifier off the mesh is a way to
%% walk the atom table until the node dies. `local/1' hands back a binary and the
%% caller displays it.
%% @end
-module(tom_names).

-export([read/1]).
-export([house/2, ship/2, ocean/1, harbour/2, good/2]).
-export([procedure/2]).
-export([facts/1]).
-export([local/1, is_harbour/1]).

-export_type([names/0]).

%% Everything this house needs to address anybody, built once at boot.
%% `harbours' and `goods' are LISTS of pairs rather than maps because the page
%% shows the ports side by side and the goods in a row, and the operator's order
%% is the order they should appear in.
-type names() :: #{realm_name := binary(),
                   house      := binary(),
                   ship       := binary(),
                   ocean      := binary(),
                   harbours   := [{binary(), binary()}],
                   goods      := [{binary(), binary()}],
                   facts      := [{atom(), binary()}]}.

%% @doc Turn a configuration into every name this house will ever use.
%%
%% Reports EVERY problem rather than the first, because a config with three
%% typos in it should cost one boot and not three.
-spec read(map()) -> {ok, names()} | {error, [term()]}.
read(Config) ->
    Realm   = maps:get(realm_name, Config),
    Singles = [{house, house(Realm, maps:get(player, Config))},
               {ship,  ship(Realm, maps:get(ship, Config))},
               {ocean, ocean(Realm)}],
    Ports   = [{N, harbour(Realm, N)} || N <- listed(maps:get(harbours, Config))],
    Wares   = [{N, good(Realm, N)}    || N <- listed(maps:get(goods, Config))],
    Faults  = faults(Singles) ++ faults(Ports) ++ faults(Wares) ++
              emptiness(Ports, Wares),
    assembled(Faults, Realm, Singles, Ports, Wares).

%% @doc The player's house. There is one, and nothing ever calls it.
-spec house(binary(), binary()) -> {ok, binary()} | {error, term()}.
house(Realm, Player) -> instance(Realm, [<<"tom">>, <<"house">>, Player]).

%% @doc The one hull.
-spec ship(binary(), binary()) -> {ok, binary()} | {error, term()}.
ship(Realm, Name) -> instance(Realm, [<<"tom">>, <<"ship">>, Name]).

%% @doc The ocean. There is exactly one, so it carries no name.
-spec ocean(binary()) -> {ok, binary()} | {error, term()}.
ocean(Realm) -> instance(Realm, [<<"tom">>, <<"ocean">>]).

%% @doc A port, as a running service rather than as a place.
%%
%% The place is reference data owned by somebody else. This is the process on a
%% box that answers calls, which is why it is an instance and not a class.
-spec harbour(binary(), binary()) -> {ok, binary()} | {error, term()}.
harbour(Realm, Name) -> instance(Realm, [<<"tom">>, <<"harbour">>, Name]).

%% @doc A good, as a kind of thing. Forty tons of pepper is not a particular
%% thing with a name, it is a quantity under this class inside some hold.
-spec good(binary(), binary()) -> {ok, binary()} | {error, term()}.
good(Realm, Name) ->
    macula_mri:new(class, Realm, [<<"tom">>, <<"good">>, Name]).

%% @doc Where a call has to land.
%%
%% Both ports advertise buy_cargo, and macula:call is first-success across the
%% pool, so a procedure name that did not carry the harbour would deliver a Macao
%% order to Lisbon. The instance MRI is the address.
-spec procedure(binary(), binary()) -> binary().
procedure(InstanceMRI, Declared) ->
    macula_mri:derive_procedure(InstanceMRI, Declared).

%% @doc The seven topics this house listens to, and what each one is.
%%
%% No identifier appears in a topic. The harbour, the ship and the good are in
%% the payload, which is what lets a house subscribe to seven topics rather than
%% seven times the number of ports.
-spec facts(binary()) -> [{atom(), binary()}].
facts(Realm) ->
    [{cargo_loaded,     fact(Realm, <<"harbour">>, <<"trade">>,   <<"cargo_loaded">>)},
     {cargo_discharged, fact(Realm, <<"harbour">>, <<"trade">>,   <<"cargo_discharged">>)},
     {ship_moored,      fact(Realm, <<"harbour">>, <<"custody">>, <<"ship_moored">>)},
     {ship_consigned,   fact(Realm, <<"harbour">>, <<"custody">>, <<"ship_consigned">>)},
     {ship_sailed,      fact(Realm, <<"ocean">>,   <<"voyage">>,  <<"ship_sailed">>)},
     {landfall_made,    fact(Realm, <<"ocean">>,   <<"voyage">>,  <<"landfall_made">>)},
     {ship_lost,        fact(Realm, <<"ocean">>,   <<"voyage">>,  <<"ship_lost">>)}].

%% @doc The last segment of an MRI, for showing a human.
%%
%% Hands back a binary, always. An unparseable identifier comes back whole,
%% because a page that shows a strange string is better than a page that crashes,
%% and because whoever sent it owns its content.
-spec local(binary()) -> binary().
local(MRI) when is_binary(MRI) -> tail(macula_mri:parse(MRI), MRI);
local(Other)                   -> iolist_to_binary(io_lib:format("~p", [Other])).

%% @doc Whether an identifier is shaped like a harbour this game could have.
%%
%% A parse, never a lookup. Nothing here has a directory and nothing here can
%% know whether Lisbon exists, only whether the name is the right shape.
-spec is_harbour(term()) -> boolean().
is_harbour(MRI) when is_binary(MRI) -> harbour_shaped(macula_mri:parse(MRI));
is_harbour(_)                       -> false.

%%% Internal

%% A list of names, or one binary with commas in it.
%%
%% Both forms exist because a `sys.config.src' substitutes shell variables into a
%% file of Erlang terms and cannot produce a list of variable length: a template
%% can write `[<<"${TOM_GOODS}">>]' and get exactly one good, forever. A
%% container therefore says "pepper,nutmeg,raw_silk" and a hand-written config
%% says the list. One rule, and the same names come out either way.
listed(Bin) when is_binary(Bin) ->
    [Name || Part <- binary:split(Bin, <<",">>, [global]),
             Name <- [string:trim(Part)],
             Name =/= <<>>];
listed(Names) when is_list(Names) ->
    Names.

instance(Realm, Path) -> macula_mri:new(instance, Realm, Path).

fact(Realm, App, Domain, Name) ->
    macula_topic:app_fact(Realm, <<"tom">>, App, Domain, Name, 1).

faults(Pairs) -> [{Label, Why} || {Label, {error, Why}} <- Pairs].

%% A game with no port, or with nothing to trade in it, is not a game. Both are
%% configuration mistakes that look like an empty page at runtime.
emptiness(Ports, Wares) -> no_ports(Ports) ++ no_goods(Wares).

no_ports([]) -> [{harbours, none_configured}];
no_ports(_)  -> [].

no_goods([]) -> [{goods, none_configured}];
no_goods(_)  -> [].

assembled([], Realm, Singles, Ports, Wares) ->
    {ok, #{realm_name => Realm,
           house      => taken(house, Singles),
           ship       => taken(ship, Singles),
           ocean      => taken(ocean, Singles),
           harbours   => [{N, M} || {N, {ok, M}} <- Ports],
           goods      => [{N, M} || {N, {ok, M}} <- Wares],
           facts      => facts(Realm)}};
assembled(Faults, _Realm, _Singles, _Ports, _Wares) ->
    {error, Faults}.

taken(Key, Singles) -> unwrapped(proplists:get_value(Key, Singles)).

unwrapped({ok, MRI}) -> MRI.

tail({ok, #{path := Path}}, MRI) -> last_or(Path, MRI);
tail({error, _}, MRI)            -> MRI.

last_or([], MRI) -> MRI;
last_or(Path, _) -> lists:last(Path).

harbour_shaped({ok, #{type := instance, path := [<<"tom">>, <<"harbour">>, _]}}) -> true;
harbour_shaped(_) -> false.
