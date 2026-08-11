%% @doc The mesh, as this house sees it: one pool, one realm tag, and the
%% translation of everything that can go wrong into refused or unreachable.
%%
%% The pool and the realm tag both come from hecate_om, which dials out to a
%% macula-station and holds the handle. A house needs no inbound port and
%% advertises no procedure: nothing on the mesh ever calls it, which is exactly
%% why it can be shut down for a whole voyage.
%%
%% NO MESH IS UNREACHABLE, NOT REFUSED. At boot the pool takes a few seconds to
%% attach and hecate_om answers `no_client' in the meantime. An order placed in
%% that window must survive to be retried, so a missing pool has to land on the
%% transient side of the taxonomy.
%% @end
-module(tom_wire_macula).
-behaviour(tom_wire).

-export([call/3, subscribe/2]).
-export([classify/1]).

%% The code the SDK stamps on a frame when the far handler returned an error
%% tuple. That is an application-level "no" and this contract calls it final.
-define(HANDLER_SAID_NO, 16#0F).

%% The code for a handler that crashed, and the code for a procedure nothing is
%% advertising. Both are worth retrying: the first may have been a bad moment,
%% the second is a service that has not come up yet.
-define(HANDLER_CRASHED, 16#02).
-define(NOBODY_ADVERTISING, 16#01).

-spec call(binary(), map(), pos_integer()) -> tom_wire:answer().
call(Procedure, Payload, TimeoutMs) ->
    reached(hecate_om:macula_client(), hecate_om_identity:realm(),
            Procedure, Payload, TimeoutMs).

-spec subscribe(binary(), pid()) -> {ok, reference()} | {error, term()}.
subscribe(Topic, Subscriber) ->
    bound(hecate_om:macula_client(), hecate_om_identity:realm(), Topic, Subscriber).

%%% Internal

reached({ok, Pool}, {ok, RealmTag}, Procedure, Payload, TimeoutMs) ->
    classify(accepted(catch macula:call(Pool, RealmTag, Procedure, Payload,
                                        TimeoutMs)));
reached(_Pool, _Realm, _Procedure, _Payload, _TimeoutMs) ->
    {unreachable, no_mesh}.

%% THE ONE PLACE A REPLY COMES IN. A receipt's keys do not arrive in the shape
%% the harbour wrote them (see tom_wire_accept), and a receipt whose `coin' the
%% house cannot find is an order that never settles and a purse that never
%% moves. Only the success shape is touched; an error is the SDK's own term.
accepted({ok, Reply}) -> {ok, tom_wire_accept:payload(Reply)};
accepted(Other)       -> Other.

bound({ok, Pool}, {ok, RealmTag}, Topic, Subscriber) ->
    listening(catch macula:subscribe(Pool, RealmTag, Topic, Subscriber));
bound(_Pool, _Realm, _Topic, _Subscriber) ->
    {error, no_mesh}.

listening({ok, Ref}) -> {ok, Ref};
listening(Other)     -> {error, Other}.

%% @doc Turn one answer from the SDK into refused or unreachable.
%%
%% A reply that is a map is the only success shape in the contract. Anything else
%% the far side managed to send is a refusal, because a house that carried on
%% with a term it does not understand would be inventing a receipt.
%%
%% A REPLY CARRYING `refused' IS A NO, WITH ITS REASON INTACT. The harbours send
%% a refusal as a successful reply with the reason in it, and it is read here
%% before the plain-map clause below.
%%
%% That shape was originally a workaround: before macula 8.0.0 the reason binary
%% in `{error, Binary}' did not survive the mesh, because the SDK rendered it
%% into a BOLT#4 frame's `detail' and its caller path read only the code, so
%% every refusal in the game arrived as one indistinguishable
%% `{call_error, 15, unknown_error}'. Since 8.0.0 a refusal arrives whole as
%% `{error, Binary}' and is classified as such below. The reply-carrying shape is
%% kept anyway, because a refusal is an ordinary outcome rather than an error and
%% reads better as one.
-spec classify(term()) -> tom_wire:answer().
classify({ok, #{<<"refused">> := Reason}}) ->
    {refused, Reason};
classify({ok, Reply}) when is_map(Reply) ->
    {ok, Reply};
classify({ok, {error, Reason}}) ->
    {refused, Reason};
classify({ok, Other}) ->
    {refused, {unexpected_reply, Other}};
classify({error, {call_error, Code, Name}}) ->
    verdict(Code, Name);
%% Since macula 8.0.0 a handler's `{error, Reason}' arrives with the reason
%% intact rather than as a code. It is a refusal and it is FINAL: re-asking a
%% harbour that has just said `hold_full' is how a client spins. Without this
%% clause the catch-all below would call it unreachable and the order would be
%% retried until it timed out.
classify({error, Reason}) when is_binary(Reason) ->
    {refused, Reason};
classify({error, Reason}) ->
    {unreachable, Reason};
classify({'EXIT', Reason}) ->
    {unreachable, Reason}.

verdict(?HANDLER_SAID_NO, Name) ->
    {refused, {call_error, ?HANDLER_SAID_NO, Name}};
verdict(?HANDLER_CRASHED, Name) ->
    {unreachable, {call_error, ?HANDLER_CRASHED, Name}};
verdict(?NOBODY_ADVERTISING, Name) ->
    {unreachable, {call_error, ?NOBODY_ADVERTISING, Name}};
verdict(Code, Name) ->
    graded(retryable(Code), Code, Name).

graded(true, Code, Name)  -> {unreachable, {call_error, Code, Name}};
graded(false, Code, Name) -> {refused, {call_error, Code, Name}}.

%% The SDK publishes a retry policy per code. Ask it rather than keeping a
%% second copy of the table here, which would rot the moment BOLT#4 grew a code.
%% An unknown code is treated as worth retrying: the alternative is to abandon an
%% order because a version of the protocol moved on.
retryable(Code) ->
    try macula_bolt4:is_retryable(Code)
    catch _:_ -> true
    end.
