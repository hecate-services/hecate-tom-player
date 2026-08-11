%% @doc What a receipt looks like by the time this house reads it, which is not
%% what the harbour wrote.
%%
%% The shapes below were taken from a real call answered by a real harbour
%% through a real station, not imagined. macula ships a binary key as a CBOR
%% text string, and `macula_frame:from_wire_envelope/1' then runs
%% `binary_to_existing_atom' over every one of them: a key whose name is already
%% in this node's atom table arrives as an ATOM, one whose name is not arrives
%% as `{text, Binary}'. One receipt carries both, and which shape a given key
%% takes is a property of THIS NODE rather than of the message.
%%
%% A house that read a receipt raw would find no `<<"coin">>' in it, leave the
%% order open and retry it forever against a harbour that has already taken the
%% money.
-module(tom_wire_accept_tests).

-include_lib("eunit/include/eunit.hrl").

-define(MACAO, <<"mri:instance:io.macula/tom/harbour/macao">>).
-define(CLARA, <<"mri:instance:io.macula/tom/ship/santa_clara">>).
-define(MUSK,  <<"mri:class:io.macula/tom/good/musk">>).

a_receipt_off_the_wire_has_binary_keys_again_test() ->
    Wire = #{order => <<"5f2c1a">>,
             {text, <<"filled">>} => 40.0,
             coin => 581.42,
             {text, <<"price_after">>} => 16.182488565095465,
             at => 1786528800000},
    ?assertEqual(#{<<"order">> => <<"5f2c1a">>,
                   <<"filled">> => 40.0,
                   <<"coin">> => 581.42,
                   <<"price_after">> => 16.182488565095465,
                   <<"at">> => 1786528800000},
                 tom_wire_accept:payload(Wire)).

%% A RECEIPT CARRIES THE SHIP, and the ship's own keys took the same beating. A
%% fold that stopped at the top level would leave the house unable to see its
%% own cargo the moment it came back off the mesh.
a_ship_inside_a_receipt_is_reached_too_test() ->
    Accepted = tom_wire_accept:payload(
                 #{{text, <<"order">>} => <<"5f2c1a">>,
                   ship => #{{text, <<"ship">>} => ?CLARA,
                             hold => 200.0,
                             cargo => #{?MUSK => 40.0},
                             {text, <<"custodian">>} => ?MACAO}}),
    Ship = maps:get(<<"ship">>, Accepted),
    ?assertEqual(?CLARA, maps:get(<<"ship">>, Ship)),
    ?assertEqual(#{?MUSK => 40.0}, maps:get(<<"cargo">>, Ship)),
    ?assertEqual(?MACAO, maps:get(<<"custodian">>, Ship)).

%% A LIST OF QUOTES IS A LIST OF MAPS, so the fold has to walk lists too or the
%% page shows a row per good with nothing in it.
quotes_in_a_list_are_reached_too_test() ->
    Accepted = tom_wire_accept:payload(
                 #{quotes => [#{good => ?MUSK,
                                {text, <<"price">>} => 12.9155,
                                stock => 43.918}]}),
    ?assertEqual([#{<<"good">> => ?MUSK, <<"price">> => 12.9155,
                    <<"stock">> => 43.918}],
                 maps:get(<<"quotes">>, Accepted)).

%% VALUES ARE NOT KEYS. `true' is what a port answered and `undefined' is a
%% field it left out; turning either into a binary would lose the answer.
accepting_a_payload_leaves_its_values_alone_test() ->
    ?assertEqual(#{<<"held">> => true, <<"moored">> => false,
                   <<"cause">> => undefined, <<"hop">> => 6,
                   <<"state">> => <<"in_passage">>},
                 tom_wire_accept:payload(#{held => true, moored => false,
                                           cause => undefined,
                                           {text, <<"hop">>} => 6,
                                           state => <<"in_passage">>})).

%% THE PAIR, WHICH IS WHAT THE TICKER TURNS ON. `watch_ports:ours/2' reads
%% `<<"ship">>' out of a fact to decide whether the publication is about this
%% house's hull. Handed a fact in the shape one actually arrives in, it says no
%% to every one of them, and the page stays empty while the ship visibly sails.
%% Through the fold first, it says yes.
a_fact_is_recognised_as_ours_only_after_the_fold_test() ->
    Wire = #{harbour => ?MACAO,
             {text, <<"ship">>} => #{{text, <<"ship">>} => ?CLARA,
                                     cargo => #{?MUSK => 40.0}},
             from => <<"mri:instance:io.macula/tom/ocean">>,
             at => 1786528800000},
    ?assertNot(watch_ports:ours(Wire, ?CLARA)),
    ?assert(watch_ports:ours(tom_wire_accept:payload(Wire), ?CLARA)).

%% NOT ONE ATOM IS MINTED. Every conversion goes from an atom the decoder
%% already had to a binary, so a stranger cannot walk the atom table until this
%% node dies.
accepting_a_payload_mints_no_atom_test() ->
    Before = erlang:system_info(atom_count),
    _ = tom_wire_accept:payload(
          #{{text, <<"a_name_no_module_in_this_release_uses">>} => <<"x">>}),
    ?assertEqual(Before, erlang:system_info(atom_count)).
