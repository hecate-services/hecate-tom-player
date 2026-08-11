%% @doc The house's own durable log. Everything it must not forget is here.
%%
%% This exists so a house can be killed between deciding to buy and hearing
%% whether it did, and still know on the way back up that it has an order
%% outstanding. Without that the reliability pattern the whole contract rests on
%% (write intent, call, retry with the same key, settle) has nowhere to write
%% the intent, and a crash silently loses a purchase or pays for one twice.
%%
%% An append-only file of length-prefixed terms. One `file:sync' per record,
%% which is the point: a record that has not reached the disk is not a record,
%% and the house replies to nobody until it has.
%%
%% A CRASH DURING A WRITE LEAVES A PARTIAL RECORD, and `open/1' repairs it by
%% truncating back to the last whole one. Leaving the stub in place would be
%% worse than losing it: the next append would run on after a half record and
%% every read from that point on would be garbage, so one lost intent would cost
%% the entire history behind it.
%% @end
-module(tom_ledger).

-export([open/1, close/1, append/2, read/1]).

-export_type([ledger/0]).

-opaque ledger() :: #{path := file:filename_all(), fd := file:fd()}.

%% Four bytes of length in front of every record. Big-endian so a hexdump of a
%% damaged file is readable by a human at three in the morning.
-define(LEN_BITS, 32).

%% @doc Open the log, repair any partial tail, and hand back everything already
%% written along with a handle to add to.
%%
%% Returns the history in the order it was written, which is the order it has to
%% be folded in.
-spec open(file:filename_all()) -> {ok, ledger(), [term()]} | {error, term()}.
open(Path) ->
    made(filelib:ensure_dir(Path), Path).

%% @doc Close the log. The file is consistent at every instant, so this is
%% politeness rather than safety.
-spec close(ledger()) -> ok.
close(#{fd := Fd}) -> file:close(Fd).

%% @doc Append one fact and put it on the disk before returning.
%%
%% The sync is not optional and must not become optional. Every caller of this
%% function is about to tell somebody else that something happened.
-spec append(ledger(), term()) -> ok | {error, term()}.
append(#{fd := Fd}, Fact) ->
    Bin = term_to_binary(Fact),
    synced(file:write(Fd, <<(byte_size(Bin)):?LEN_BITS, Bin/binary>>), Fd).

%% @doc Everything in a log, without opening it for writing. For inspecting a
%% house's history from a shell without disturbing the house.
-spec read(file:filename_all()) -> {ok, [term()]} | {error, term()}.
read(Path) -> scanned(file:read_file(Path)).

%%% Internal

made(ok, Path)             -> loaded(file:read_file(Path), Path);
made({error, _} = Err, _P) -> Err.

%% A log that is not there yet is an empty history, not a fault. That is a house
%% opening for the first time, and it is the only moment its genesis purse is
%% allowed to apply.
loaded({error, enoent}, Path) -> opened(Path, [], 0, 0);
loaded({error, _} = Err, _)   -> Err;
loaded({ok, Bin}, Path)       -> whole(Bin, Path).

whole(Bin, Path) ->
    {Facts, Good} = walk(Bin, 0, []),
    opened(Path, Facts, Good, byte_size(Bin)).

%% Truncate only when there is something after the last whole record. Opening
%% for `append' would otherwise write past the stub and corrupt everything after
%% it, which is how one interrupted write costs a whole history.
opened(Path, Facts, Good, Size) when Good < Size ->
    trimmed(Path, Facts, Good, file:open(Path, [read, write, raw, binary]));
opened(Path, Facts, _Good, _Size) ->
    held(Path, Facts, file:open(Path, [append, raw, binary])).

trimmed(Path, Facts, Good, {ok, Fd}) ->
    {ok, Good} = file:position(Fd, Good),
    ok = file:truncate(Fd),
    ok = file:close(Fd),
    logger:warning("[tom_ledger] repaired a partial tail in ~ts at byte ~p",
                   [Path, Good]),
    held(Path, Facts, file:open(Path, [append, raw, binary]));
trimmed(_Path, _Facts, _Good, {error, _} = Err) ->
    Err.

held(Path, Facts, {ok, Fd})          -> {ok, #{path => Path, fd => Fd}, Facts};
held(_Path, _Facts, {error, _} = Err) -> Err.

scanned({ok, Bin})       -> {ok, element(1, walk(Bin, 0, []))};
scanned({error, enoent}) -> {ok, []};
scanned({error, _} = E)  -> E.

%% Walk the records, remembering the offset after the last whole one. A short
%% length prefix, a short body, or a body that will not decode all stop the walk
%% at the same place: everything before it is history, everything after is the
%% remains of an interrupted write.
walk(<<Len:?LEN_BITS, Body:Len/binary, Rest/binary>>, Offset, Acc) ->
    Next = Offset + 4 + Len,
    decoded(catch binary_to_term(Body), Rest, Next, Offset, Acc);
walk(_Remainder, Offset, Acc) ->
    {lists:reverse(Acc), Offset}.

decoded({'EXIT', _}, _Rest, _Next, Offset, Acc) ->
    {lists:reverse(Acc), Offset};
decoded(Fact, Rest, Next, _Offset, Acc) ->
    walk(Rest, Next, [Fact | Acc]).

synced(ok, Fd)              -> file:sync(Fd);
synced({error, _} = Err, _) -> Err.
