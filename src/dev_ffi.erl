-module(dev_ffi).
-export([run_command/2, run_command_in/3, run_background/3, get_today/0]).

run_command(Cmd, Args) ->
    run_command_in(Cmd, Args, ".").

run_command_in(Cmd, Args, Cwd) ->
    ArgsList = [to_list(A) || A <- Args],
    CwdStr = to_list(Cwd),
    CmdStr = to_list(Cmd),
    FilteredArgs = ["\"" ++ A ++ "\"" || A <- ArgsList, A =/= ""],
    FullCmd = "cd " ++ CwdStr ++ " && " ++ CmdStr ++ " " ++ string:join(FilteredArgs, " "),
    try
        Output = os:cmd(FullCmd ++ "; printf '\\n__FUSION_STATUS:%s\\n' \"$?\""),
        command_result(Output, FullCmd)
    catch
        error:Reason ->
            Msg = iolist_to_binary(io_lib:format("~p", [Reason])),
            {error, iolist_to_binary([<<"Failed: ">>, iolist_to_binary(FullCmd), <<" - ">>, Msg])}
    end.

command_result(Output, FullCmd) ->
    Marker = "__FUSION_STATUS:",
    case string:split(Output, Marker, all) of
        [CommandOutput, StatusWithRest] ->
            Status = hd(string:split(StatusWithRest, "\n", all)),
            case Status of
                "0" -> {ok, unicode:characters_to_binary(CommandOutput)};
                _ -> {error, unicode:characters_to_binary(["Command failed: ", FullCmd, "\n", CommandOutput])}
            end;
        _ ->
            {error, unicode:characters_to_binary(["Could not determine command status: ", FullCmd])}
    end.

to_list(Data) when is_binary(Data) -> binary_to_list(Data);
to_list(Data) when is_list(Data) -> Data;
to_list(Data) -> lists:flatten(io_lib:format("~p", [Data])).

run_background(Cmd, Args, Cwd) ->
    ArgsList = [to_list(A) || A <- Args],
    CwdStr = to_list(Cwd),
    CmdStr = to_list(Cmd),
    FilteredArgs = ["\"" ++ A ++ "\"" || A <- ArgsList, A =/= ""],
    FullCmd = "cd " ++ CwdStr ++ " && " ++ CmdStr ++ " " ++ string:join(FilteredArgs, " "),
    Port = open_port({spawn, "/bin/sh -c '" ++ FullCmd ++ "'"}, [exit_status, binary, eof, {line, 1024}]),
    port_loop(Port).

port_loop(Port) ->
    receive
        {Port, {data, {eol, Data}}} ->
            io:format("~ts~n", [Data]),
            port_loop(Port);
        {Port, {data, {noeol, Data}}} ->
            io:format("~ts", [Data]),
            port_loop(Port);
        {Port, eof} ->
            {ok, <<>>};
        {Port, {exit_status, 0}} ->
            {ok, <<>>};
        {Port, {exit_status, Status}} ->
            {error, iolist_to_binary(io_lib:format("Process exited with status ~p", [Status]))}
    end.

get_today() ->
    Timestamp = erlang:timestamp(),
    {Date, _Time} = calendar:now_to_universal_time(Timestamp),
    {Year, Month, Day} = Date,
    Formatted = io_lib:format("~4..0B-~2..0B-~2..0B", [Year, Month, Day]),
    unicode:characters_to_binary(Formatted).
