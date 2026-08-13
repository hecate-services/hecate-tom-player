%% @doc The names, checked against the contract's own literal strings.
%%
%% This suite exists because a name is the one thing three services built by
%% three different hands have to agree on to the byte. Everything else can be
%% negotiated at runtime; a procedure name that is one character off is a call
%% that lands nowhere and an error nobody can read.
-module(tom_names_tests).

-include_lib("eunit/include/eunit.hrl").

-define(REALM, <<"io.macula">>).

house_is_an_instance_test() ->
    ?assertEqual({ok, <<"mri:instance:io.macula/tom/house/raf">>},
                 tom_names:house(?REALM, <<"raf">>)).

ship_is_an_instance_test() ->
    ?assertEqual({ok, <<"mri:instance:io.macula/tom/ship/santa_clara">>},
                 tom_names:ship(?REALM, <<"santa_clara">>)).

%% No identifier is ever in a topic. That is what lets a house subscribe to six
%% topics rather than six times the number of ports.
the_six_topics_test() ->
    Facts = tom_names:facts(?REALM),
    ?assertEqual(6, length(Facts)),
    ?assertEqual(<<"io.macula/tom/harbour/trade/cargo_loaded_v1">>,
                 proplists:get_value(cargo_loaded, Facts)),
    ?assertEqual(<<"io.macula/tom/harbour/trade/cargo_discharged_v1">>,
                 proplists:get_value(cargo_discharged, Facts)),
    ?assertEqual(<<"io.macula/tom/harbour/custody/ship_moored_v1">>,
                 proplists:get_value(ship_moored, Facts)),
    ?assertEqual(<<"io.macula/tom/harbour/custody/ship_consigned_v1">>,
                 proplists:get_value(ship_consigned, Facts)),
    ?assertEqual(<<"io.macula/tom/harbour/voyage/ship_sailed_v1">>,
                 proplists:get_value(ship_sailed, Facts)),
    ?assertEqual(<<"io.macula/tom/harbour/voyage/ship_lost_v1">>,
                 proplists:get_value(ship_lost, Facts)).

reading_a_configuration_test() ->
    {ok, Names} = tom_names:read(config()),
    ?assertEqual(<<"mri:instance:io.macula/tom/house/raf">>, maps:get(house, Names)),
    ?assertEqual([{<<"macao">>, <<"mri:instance:io.macula/tom/harbour/macao">>},
                  {<<"lisbon">>, <<"mri:instance:io.macula/tom/harbour/lisbon">>}],
                 maps:get(harbours, Names)),
    ?assertEqual(6, length(maps:get(facts, Names))).

%% Order is the operator's order, because it is the order the page shows.
configured_order_is_kept_test() ->
    {ok, Names} = tom_names:read((config())#{harbours => [<<"lisbon">>, <<"macao">>]}),
    ?assertEqual([<<"lisbon">>, <<"macao">>],
                 [Local || {Local, _MRI} <- maps:get(harbours, Names)]).

%% Every problem, not the first. A config with three typos costs one boot.
every_fault_is_reported_test() ->
    Broken = (config())#{player => <<"Raf Lefever">>, goods => [<<"Pepper!">>]},
    {error, Faults} = tom_names:read(Broken),
    ?assertEqual(2, length(Faults)).

%% A container's sys.config.src cannot write a list of variable length, so it
%% says "macao,lisbon" and gets the same two names.
a_comma_separated_list_is_a_list_test() ->
    {ok, Names} = tom_names:read((config())#{harbours => <<"macao, lisbon">>,
                                             goods    => <<"pepper,nutmeg">>}),
    ?assertEqual([<<"macao">>, <<"lisbon">>],
                 [Local || {Local, _MRI} <- maps:get(harbours, Names)]),
    ?assertEqual([<<"pepper">>, <<"nutmeg">>],
                 [Local || {Local, _MRI} <- maps:get(goods, Names)]).

an_empty_comma_list_is_no_ports_test() ->
    ?assertMatch({error, [{harbours, none_configured}]},
                 tom_names:read((config())#{harbours => <<"">>})).

a_game_needs_a_port_test() ->
    {error, Faults} = tom_names:read((config())#{harbours => []}),
    ?assertMatch([{harbours, none_configured}], Faults).

a_game_needs_something_to_trade_test() ->
    {error, Faults} = tom_names:read((config())#{goods => []}),
    ?assertMatch([{goods, none_configured}], Faults).

%% Displaying a name never mints an atom, because atoms are not collected and
%% anything off the mesh is a stranger's bytes.
local_name_never_mints_an_atom_test() ->
    Before = erlang:system_info(atom_count),
    Names = [<<"mri:instance:io.macula/tom/harbour/",
               (integer_to_binary(N))/binary>> || N <- lists:seq(1, 500)],
    _ = [tom_names:local(N) || N <- Names],
    ?assertEqual(Before, erlang:system_info(atom_count)).

local_name_of_a_harbour_test() ->
    ?assertEqual(<<"macao">>,
                 tom_names:local(<<"mri:instance:io.macula/tom/harbour/macao">>)).

%% A page that shows a strange string beats a page that crashes.
local_name_of_nonsense_test() ->
    ?assertEqual(<<"not an mri at all">>, tom_names:local(<<"not an mri at all">>)).

%% A parse, never a lookup. This house has no directory.
harbour_shape_test() ->
    ?assert(tom_names:is_harbour(<<"mri:instance:io.macula/tom/harbour/lisbon">>)),
    ?assertNot(tom_names:is_harbour(<<"mri:instance:io.macula/tom/world">>)),
    ?assertNot(tom_names:is_harbour(<<"mri:class:io.macula/tom/harbour/lisbon">>)),
    ?assertNot(tom_names:is_harbour(<<"lisbon">>)),
    ?assertNot(tom_names:is_harbour(undefined)).

config() ->
    #{realm_name => ?REALM,
      player     => <<"raf">>,
      ship       => <<"santa_clara">>,
      harbours   => [<<"macao">>, <<"lisbon">>],
      goods      => [<<"pepper">>, <<"nutmeg">>]}.
