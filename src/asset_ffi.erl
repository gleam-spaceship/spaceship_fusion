-module(asset_ffi).
-export([read_asset/1]).

read_asset(Path) ->
    case file:read_file(Path) of
        {ok, Data} -> {ok, Data};
        {error, Reason} -> {error, iolist_to_binary(io_lib:format("Could not read ~s: ~p", [Path, Reason]))}
    end.
