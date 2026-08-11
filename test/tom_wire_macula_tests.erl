%% @doc The one distinction the whole reliability pattern rests on.
%%
%% Getting it backwards is expensive in both directions. Retrying a refusal loops
%% forever against a harbour that will never change its mind; treating a timeout
%% as a refusal abandons an order the harbour may well have executed, and the
%% pepper is then in the hold with nobody having paid for it.
-module(tom_wire_macula_tests).

-include_lib("eunit/include/eunit.hrl").

a_map_is_the_only_success_test() ->
    ?assertEqual({ok, #{<<"coin">> => 581.42}},
                 tom_wire_macula:classify({ok, #{<<"coin">> => 581.42}})).

%% A REFUSAL ARRIVES AS A REPLY, WITH ITS REASON ON IT. `{error, Binary}' does
%% not carry the reason across: macula renders it into a BOLT#4 frame's `detail'
%% and the SDK's caller path reads only the code, so quay_empty, hold_full,
%% not_here and the rest all reach this house as one indistinguishable
%% `{call_error, 15, unknown_error}'. The harbours therefore answer a refusal
%% with a reply that says so, which is the one shape the wire keeps whole.
%%
%% It is still a refusal, so it is still FINAL: the order closes and the player
%% is told, rather than the house re-asking a port that will not change its mind.
a_reply_carrying_a_refusal_is_a_refusal_test() ->
    ?assertEqual({refused, <<"hold_full">>},
                 tom_wire_macula:classify({ok, #{<<"refused">> => <<"hold_full">>}})),
    ?assertEqual({refused, <<"not_here">>},
                 tom_wire_macula:classify({ok, #{<<"refused">> => <<"not_here">>}})).

%% And a receipt is not a refusal because it mentions coin. The two shapes are
%% told apart by one key and nothing else.
a_receipt_is_not_a_refusal_test() ->
    ?assertMatch({ok, _},
                 tom_wire_macula:classify(
                   {ok, #{<<"order">> => <<"5f2c1a">>, <<"coin">> => 581.42,
                          <<"filled">> => 40.0}})).

%% 0x0F is the code the SDK stamps on a frame when the far handler returned an
%% error tuple. An enumerated reason is FINAL, so this must never be retried,
%% whatever macula_bolt4's own retry policy says about the code.
a_handler_saying_no_is_final_test() ->
    ?assertMatch({refused, _},
                 tom_wire_macula:classify({error, {call_error, 16#0F, unknown_error}})).

%% 0x02 is a handler that crashed. That is a bad moment, not a decision.
a_handler_that_crashed_is_worth_retrying_test() ->
    ?assertMatch({unreachable, _},
                 tom_wire_macula:classify(
                   {error, {call_error, 16#02, temporary_relay_failure}})).

%% 0x01 is nothing advertising the procedure, which is a port that has not come
%% up yet. Abandoning an order for that would be abandoning it for a service
%% that is about to start.
nobody_advertising_is_worth_retrying_test() ->
    ?assertMatch({unreachable, _},
                 tom_wire_macula:classify(
                   {error, {call_error, 16#01, unknown_next_peer}})).

a_timeout_is_worth_retrying_test() ->
    ?assertEqual({unreachable, timeout}, tom_wire_macula:classify({error, timeout})).

no_station_is_worth_retrying_test() ->
    ?assertEqual({unreachable, no_healthy_station},
                 tom_wire_macula:classify({error, no_healthy_station})).

a_dropped_link_is_worth_retrying_test() ->
    ?assertMatch({unreachable, {disconnected, _}},
                 tom_wire_macula:classify({error, {disconnected, closed}})).

%% Belt and braces. A RESULT frame carrying an error tuple should not be
%% reachable through the current SDK, but if one ever arrives it is an answer
%% and answers are final.
an_error_tuple_in_a_result_is_final_test() ->
    ?assertEqual({refused, <<"hold_full">>},
                 tom_wire_macula:classify({ok, {error, <<"hold_full">>}})).

%% Carrying on with a term the house does not understand would be inventing a
%% receipt out of somebody else's mistake.
%% Since macula 8.0.0 a handler refusal arrives whole rather than as a code, and
%% it must be classified as a REFUSAL. Before this clause existed the catch-all
%% called it unreachable, which means the house would have retried an order the
%% harbour had already turned down, until it timed out.
a_bare_binary_reason_is_a_refusal_not_a_failure_test() ->
    ?assertEqual({refused, <<"hold_full">>},
                 tom_wire_macula:classify({error, <<"hold_full">>})),
    ?assertEqual({refused, <<"not_enough_coin">>},
                 tom_wire_macula:classify({error, <<"not_enough_coin">>})).

%% And an atom reason is still the transport, not a handler. Only a binary
%% crosses the mesh as a reason.
a_bare_atom_reason_is_still_unreachable_test() ->
    ?assertEqual({unreachable, timeout},
                 tom_wire_macula:classify({error, timeout})).

a_reply_that_is_not_a_map_is_refused_test() ->
    ?assertMatch({refused, {unexpected_reply, <<"yes">>}},
                 tom_wire_macula:classify({ok, <<"yes">>})).

a_crash_in_the_sdk_is_worth_retrying_test() ->
    ?assertMatch({unreachable, _}, tom_wire_macula:classify({'EXIT', badarg})).

%% An unknown code means the protocol moved on. Abandoning an order over that
%% would be losing money to a version number.
an_unknown_code_is_worth_retrying_test() ->
    ?assertMatch({unreachable, _},
                 tom_wire_macula:classify({error, {call_error, 200, whatever}})).
