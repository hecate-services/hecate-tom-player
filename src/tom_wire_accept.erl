%% @doc What this house reads off the mesh, once the codec has finished with it.
%%
%% THE CONTRACT SAYS EVERY KEY ON THE WIRE IS A BINARY. That is true of what a
%% SENDER writes and false of what a RECEIVER gets, and the whole of this module
%% is the difference.
%%
%% macula's CBOR codec ships a binary key as a major-3 text string. Coming back
%% in, `macula_frame:from_wire_envelope/1' runs `binary_to_existing_atom' over
%% every key: one whose name is already in this node's atom table arrives as an
%% ATOM, one whose name is not arrives as `{text, Binary}'. A single receipt can
%% therefore carry `coin' as an atom and `{text, <<"price_after">>}' beside it,
%% and WHICH SHAPE A KEY TAKES IS A PROPERTY OF THIS NODE, not of the message:
%% loading any module that mentions the atom `coin' changes it, quietly, for
%% every payload afterwards.
%%
%% A house that read a receipt raw would find no `<<"coin">>' in it, leave the
%% order open and retry it forever against a harbour that has already taken the
%% money. So every reply and every fact goes through here first, and the slices
%% downstream read the binary keys they were written against.
%%
%% NOTHING HERE MINTS AN ATOM. `atom_to_binary' only unmakes one the decoder
%% already had, so a stranger cannot walk the atom table from the wire.
-module(tom_wire_accept).

-export([payload/1]).

%% @doc Put a payload back into the shape this house reads: binary keys, all the
%% way down.
%%
%% Values are left alone apart from the same text unwrapping, because `true',
%% `false' and `undefined' are atoms this game means rather than codec debris.
-spec payload(term()) -> term().
payload(Map) when is_map(Map) ->
    maps:fold(fun(Key, Value, Acc) -> Acc#{binary_key(Key) => payload(Value)} end,
              #{}, Map);
payload(Values) when is_list(Values) ->
    [payload(Value) || Value <- Values];
payload({text, Text}) when is_binary(Text) ->
    Text;
payload(Other) ->
    Other.

%%% Internal

binary_key({text, Text}) when is_binary(Text) -> Text;
binary_key(Key) when is_atom(Key) -> atom_to_binary(Key, utf8);
binary_key(Key) -> Key.
