%% @doc How this house reaches the ports and the ocean, and how it tells a "no"
%% from a "not now".
%%
%% This exists because the whole reliability pattern turns on ONE distinction:
%%
%%   refused     the far side answered, and the answer was no. FINAL. Do not
%%               retry it, ever. Close the order and tell the player.
%%   unreachable the far side did not answer. TRANSIENT. Retry with the SAME
%%               key until it does. The receipt is waiting there for us.
%%
%% Getting that backwards is expensive in both directions. Retrying a refusal
%% loops forever against a harbour that will never change its mind. Treating a
%% timeout as a refusal abandons an order the harbour may well have executed,
%% and the pepper is then in the hold with nobody having paid for it.
%%
%% == The taxonomy, as the mesh actually delivers it ==
%%
%% A handler on the far side that returns `{error, Reason}' arrives here as
%% `{error, Reason}', reason intact, and is refused and FINAL.
%%
%% That is true as of macula 8.0.0 and was not true before it. The SDK turned a
%% refusal into a BOLT#4 error frame with code 0x0F, carried the reason in the
%% frame's `detail' field, and then dropped `detail' on the caller path, so every
%% refusal in the game arrived as `{error, {call_error, 16#0F, unknown_error}}'.
%% The house could tell THAT it had been refused and never WHY. It was found
%% building this service and fixed in the SDK rather than worked around again.
%%
%% The codes still matter, for the frames a handler did not speak:
%%
%%   0x0F  a refusal from a peer too old to send `detail' → refused, and final
%%   0x02  the handler crashed                           → unreachable, retry
%%   0x01  nothing is advertising that procedure         → unreachable, retry
%%   other → macula_bolt4:is_retryable/1 decides
%%
%% 0x0F is deliberately NOT delegated to `macula_bolt4:is_retryable/1', which
%% calls it retryable. For this contract it is not: an enumerated reason is
%% final, and re-asking a harbour that has said `hold_full' is how a client
%% spins.
%% @end
-module(tom_wire).

-export([call/3, subscribe/2]).

-export_type([answer/0]).

%% Every call to another service comes back as exactly one of these.
-type answer() :: {ok, map()}
                | {refused, term()}
                | {unreachable, term()}.

%% Reads are cheap and a slow one is not worth waiting on. Mutations and
%% handovers get the long deadline, because abandoning one costs a retry against
%% a service that may already have done the work.
-define(READ_MS, 5_000).
-define(ACT_MS, 15_000).

-callback call(Procedure :: binary(), Payload :: map(), TimeoutMs :: pos_integer()) ->
    answer().
-callback subscribe(Topic :: binary(), Subscriber :: pid()) ->
    {ok, reference()} | {error, term()}.

%% @doc Ask somebody a question.
%%
%% `read' is five seconds and `act' is fifteen, which is the split the contract
%% fixes: reads are cheap to repeat and mutations are not.
-spec call(binary(), map(), pos_integer() | read | act) -> answer().
call(Procedure, Payload, read) ->
    call(Procedure, Payload, ?READ_MS);
call(Procedure, Payload, act) ->
    call(Procedure, Payload, ?ACT_MS);
call(Procedure, Payload, TimeoutMs) when is_integer(TimeoutMs) ->
    (carrier()):call(Procedure, Payload, TimeoutMs).

%% @doc Listen for a fact. A subscription that fails to bind is not an
%% emergency: no correctness anywhere depends on a fact arriving, so the caller
%% simply tries again later.
-spec subscribe(binary(), pid()) -> {ok, reference()} | {error, term()}.
subscribe(Topic, Subscriber) -> (carrier()):subscribe(Topic, Subscriber).

%% Which implementation carries the traffic. In a running house this is the
%% mesh. In a test it is a module that answers from a script, which is how the
%% restart path is exercised without a station within a hundred kilometres.
carrier() ->
    application:get_env(hecate_tom_house, wire, tom_wire_macula).
