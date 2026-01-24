-module(git_ffi).
-export([full_hash/1, short_hash/1 ,last_change/1]).


run(Cmd) ->
    Output = os:cmd(Cmd),
    Hash = string:trim(Output),
    case Hash of
        "" -> {error, nil};
        _ -> {ok, list_to_binary(Hash)}
    end.

full_hash(Filepath) ->
    Path = unicode:characters_to_list(Filepath),
    run("git rev-list -1 HEAD -- " ++ Path).

short_hash(Filepath) ->
    Path = unicode:characters_to_list(Filepath),
    run("git rev-list --abbrev-commit -1 HEAD -- " ++ Path ).

last_change(Filepath) ->
    Path = unicode:characters_to_list(Filepath),
    run("git log -1 --format=%cI -- " ++ Path ).
