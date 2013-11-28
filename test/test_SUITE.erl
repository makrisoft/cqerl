%% common_test suite for test

-module(test_SUITE).
-include_lib("common_test/include/ct.hrl").

-include("cqerl.hrl").

-compile(export_all).

%%--------------------------------------------------------------------
%% Function: suite() -> Info
%%
%% Info = [tuple()]
%%   List of key/value pairs.
%%
%% Description: Returns list of tuples to set default properties
%%              for the suite.
%%
%% Note: The suite/0 function is only meant to be used to return
%% default data values, not perform any other operations.
%%--------------------------------------------------------------------
suite() -> 
  [{timetrap, {seconds, 20}},
   {require, ssl, cqerl_test_ssl},
   {require, auth, cqerl_test_auth},
   {require, keyspace, cqerl_test_keyspace},
   {require, host, cqerl_host}].

%%--------------------------------------------------------------------
%% Function: groups() -> [Group]
%%
%% Group = {GroupName,Properties,GroupsAndTestCases}
%% GroupName = atom()
%%   The name of the group.
%% Properties = [parallel | sequence | Shuffle | {RepeatType,N}]
%%   Group properties that may be combined.
%% GroupsAndTestCases = [Group | {group,GroupName} | TestCase]
%% TestCase = atom()
%%   The name of a test case.
%% Shuffle = shuffle | {shuffle,Seed}
%%   To get cases executed in random order.
%% Seed = {integer(),integer(),integer()}
%% RepeatType = repeat | repeat_until_all_ok | repeat_until_all_fail |
%%              repeat_until_any_ok | repeat_until_any_fail
%%   To get execution of cases repeated.
%% N = integer() | forever
%%
%% Description: Returns a list of test case group definitions.
%%--------------------------------------------------------------------
groups() -> [
    {database, [sequence], [ 
        connect, create_keyspace, create_table, 
        simple_insertion_roundtrip, async_insertion_roundtrip,
        all_datatypes
    ]}
].

%%--------------------------------------------------------------------
%% Function: all() -> GroupsAndTestCases
%%
%% GroupsAndTestCases = [{group,GroupName} | TestCase]
%% GroupName = atom()
%%   Name of a test case group.
%% TestCase = atom()
%%   Name of a test case.
%%
%% Description: Returns the list of groups and test cases that
%%              are to be executed.
%%
%%      NB: By default, we export all 1-arity user defined functions
%%--------------------------------------------------------------------
all() ->
    [datatypes_test, {group, database}].

%%--------------------------------------------------------------------
%% Function: init_per_suite(Config0) ->
%%               Config1 | {skip,Reason} | {skip_and_save,Reason,Config1}
%%
%% Config0 = Config1 = [tuple()]
%%   A list of key/value pairs, holding the test case configuration.
%% Reason = term()
%%   The reason for skipping the suite.
%%
%% Description: Initialization before the suite.
%%
%% Note: This function is free to add any key/value pairs to the Config
%% variable, but should NOT alter/remove any existing entries.
%%--------------------------------------------------------------------
init_per_suite(Config) ->
    application:ensure_all_started(cqerl),
    [ {auth, ct:get_config(auth)}, 
      {ssl, ct:get_config(ssl)}, 
      {keyspace, ct:get_config(keyspace)},
      {host, ct:get_config(host)} ] ++ Config.

%%--------------------------------------------------------------------
%% Function: end_per_suite(Config0) -> void() | {save_config,Config1}
%%
%% Config0 = Config1 = [tuple()]
%%   A list of key/value pairs, holding the test case configuration.
%%
%% Description: Cleanup after the suite.
%%--------------------------------------------------------------------
end_per_suite(_Config) ->
    ok.

%%--------------------------------------------------------------------
%% Function: init_per_group(GroupName, Config0) ->
%%               Config1 | {skip,Reason} | {skip_and_save,Reason,Config1}
%%
%% GroupName = atom()
%%   Name of the test case group that is about to run.
%% Config0 = Config1 = [tuple()]
%%   A list of key/value pairs, holding configuration data for the group.
%% Reason = term()
%%   The reason for skipping all test cases and subgroups in the group.
%%
%% Description: Initialization before each test case group.
%%--------------------------------------------------------------------

init_per_group(_group, Config) ->
    Config.

%%--------------------------------------------------------------------
%% Function: end_per_group(GroupName, Config0) ->
%%               void() | {save_config,Config1}
%%
%% GroupName = atom()
%%   Name of the test case group that is finished.
%% Config0 = Config1 = [tuple()]
%%   A list of key/value pairs, holding configuration data for the group.
%%
%% Description: Cleanup after each test case group.
%%--------------------------------------------------------------------
end_per_group(_group, Config) ->
    Config.

%%--------------------------------------------------------------------
%% Function: init_per_testcase(TestCase, Config0) ->
%%               Config1 | {skip,Reason} | {skip_and_save,Reason,Config1}
%%
%% TestCase = atom()
%%   Name of the test case that is about to run.
%% Config0 = Config1 = [tuple()]
%%   A list of key/value pairs, holding the test case configuration.
%% Reason = term()
%%   The reason for skipping the test case.
%%
%% Description: Initialization before each test case.
%%
%% Note: This function is free to add any key/value pairs to the Config
%% variable, but should NOT alter/remove any existing entries.
%%--------------------------------------------------------------------
init_per_testcase(TestCase, Config) ->
    Config.

%%--------------------------------------------------------------------
%% Function: end_per_testcase(TestCase, Config0) ->
%%               void() | {save_config,Config1} | {fail,Reason}
%%
%% TestCase = atom()
%%   Name of the test case that is finished.
%% Config0 = Config1 = [tuple()]
%%   A list of key/value pairs, holding the test case configuration.
%% Reason = term()
%%   The reason for failing the test case.
%%
%% Description: Cleanup after each test case.
%%--------------------------------------------------------------------
end_per_testcase(TestCase, Config) ->
    Config.

datatypes_test(_Config) ->
    ok = eunit:test(cqerl_datatypes).

connect(Config) ->
    {Pid, Ref} = get_client(Config),
    true = is_pid(Pid),
    true = is_reference(Ref),
    cqerl:close_client({Pid, Ref}),
    ok.

create_keyspace(Config) ->
    Client = get_client(Config),
    Q = <<"CREATE KEYSPACE test_keyspace WITH replication = {'class': 'SimpleStrategy', 'replication_factor': 1};">>,
    D = <<"DROP KEYSPACE test_keyspace;">>,
    case cqerl:run_query(Client, #cql_query{query=Q}) of
        {ok, #cql_schema_changed{change_type=created, keyspace = <<"test_keyspace">>}} -> ok;
        {error, {16#2400, _, {key_space, <<"test_keyspace">>}}} ->
            {ok, #cql_schema_changed{change_type=dropped, keyspace = <<"test_keyspace">>}} = cqerl:run_query(Client, D),
            {ok, #cql_schema_changed{change_type=created, keyspace = <<"test_keyspace">>}} = cqerl:run_query(Client, Q)
    end,
    cqerl:close_client(Client).
        
create_table(Config) ->
    Client = get_client(Config),
    Q = "CREATE TABLE entries1(id varchar, age int, email varchar, PRIMARY KEY(id));",
    {ok, #cql_schema_changed{change_type=created, keyspace = <<"test_keyspace">>, table = <<"entries1">>}} =
        cqerl:run_query(Client, Q),
    cqerl:close_client(Client).

simple_insertion_roundtrip(Config) ->
    Client = get_client(Config),
    Q = <<"INSERT INTO entries1(id, age, email) VALUES (?, ?, ?)">>,
    {ok, ok} = cqerl:run_query(Client, #cql_query{query=Q, values=[
        {id, "hello"},
        {age, 18},
        {email, <<"mathieu@damours.org">>}
    ]}),
    {ok, Result=#cql_result{}} = cqerl:run_query(Client, #cql_query{query = <<"SELECT * FROM entries1;">>}),
    Row = cqerl:head(Result),
    <<"hello">> = proplists:get_value(id, Row),
    18 = proplists:get_value(age, Row),
    <<"mathieu@damours.org">> = proplists:get_value(email, Row),
    cqerl:close_client(Client),
    Result.

async_insertion_roundtrip(Config) ->
    Client = get_client(Config),
    Q = <<"INSERT INTO entries1(id, age, email) VALUES (?, ?, ?)">>,
    Ref = cqerl:send_query(Client, #cql_query{query=Q, values=[
        {id, "1234123"},
        {age, 45},
        {email, <<"yvon@damours.org">>}
    ]}),
    Ref2 = cqerl:send_query(Client, #cql_query{query = <<"SELECT * FROM entries1;">>}),
    Flush  = fun (CB, Res) ->
        receive
            {result, Ref, ok} -> 
                CB(CB, Res);
            {result, Ref2, Result=#cql_result{}} ->
                {_Row, Result2} = cqerl:next(Result),
                Row = cqerl:head(Result2),
                <<"1234123">> = proplists:get_value(id, Row),
                45 = proplists:get_value(age, Row),
                <<"yvon@damours.org">> = proplists:get_value(email, Row),
                cqerl:close_client(Client),
                Row;
            Other2 ->
                throw({unexpected_msg, Other2})
        end
    end,
    Res = Flush(Flush, void),
    cqerl:close_client(Client),
    Res.


datatypes_columns(Cols) ->
    datatypes_columns(1, Cols, <<>>).

datatypes_columns(_I, [], Bin) -> Bin;
datatypes_columns(I, [ColumnType|Rest], Bin) ->
    Column = list_to_binary(io_lib:format("col~B ~s, ", [I, ColumnType])),
    datatypes_columns(I+1, Rest, << Bin/binary, Column/binary >>).

all_datatypes(Config) ->
    Client = get_client(Config),
    Cols = datatypes_columns([ascii, bigint, blob, boolean, decimal, double, float, int, timestamp, uuid, varchar, varint, timeuuid, inet]),
    CreationQ = <<"CREATE TABLE entries2(",  Cols/binary, " PRIMARY KEY(col1));">>,
    ct:log("Executing : ~s~n", [CreationQ]),
    {ok, #cql_schema_changed{change_type=created, keyspace = <<"test_keyspace">>, table = <<"entries2">>}} =
        cqerl:run_query(Client, CreationQ),
    
    InsQ = #cql_query{query = <<"INSERT INTO entries2(col1, col2, col3, col4, col5, col6, col7, col8, col9, col10, col11, col12, col13, col14) VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?)">>},
    {ok, ok} = cqerl:run_query(Client, InsQ#cql_query{values=RRow1=[
        {col1, "hello"},
        {col2, 9223372036854775807},
        {col3, <<1,2,3,4,5,6,7,8,9,10>>},
        {col4, true},
        {col5, {1234, 5}},
        {col6, 5.1235131241221e-6},
        {col7, 5.12351e-6},
        {col8, 2147483647},
        {col9, now},
        {col10, new},
        {col11, <<"Юникод"/utf8>>},
        {col12, 1928301970128391280192830198049113123},
        {col13, now},
        {col14, {127, 0, 0, 1}}
    ]}),
    {ok, ok} = cqerl:run_query(Client, InsQ#cql_query{values=RRow2=[
        {col1, <<"foobar">>},
        {col2, -9223372036854775806},
        {col3, <<1,2,3,4,5,6,7,8,9,10>>},
        {col4, false},
        {col5, {1234, -5}},
        {col6, -5.1235131241220e-6},
        {col7, -5.12351e-6},
        {col8, -2147483646},
        {col9, 1984336643},
        {col10, <<22,6,195,126,110,122,64,242,135,15,38,179,46,108,22,64>>},
        {col11, <<"åäö"/utf8>>},
        {col12, 123124211928301970128391280192830198049113123},
        {col13, <<250,10,224,94,87,197,17,227,156,99,146,79,0,0,0,195>>},
        {col14, {0,0,0,0,0,0,0,0}}
    ]}),
    
    {ok, Result=#cql_result{}} = cqerl:run_query(Client, #cql_query{query = <<"SELECT * FROM entries2;">>}),
    {Row1, Result1} = cqerl:next(Result),
    Row2 = cqerl:head(Result1),
    lists:foreach(fun
        (Row) -> 
            ReferenceRow = case proplists:get_value(col1, Row) of
                <<"hello">> -> RRow1;
                <<"foobar">> -> RRow2
            end,
            lists:foreach(fun
                ({col13, _}) -> true = uuid:is_v1(proplists:get_value(col13, Row));
                ({col10, _}) -> true = uuid:is_v4(proplists:get_value(col10, Row));
                ({col9, _}) -> ok;
                ({col1, Key}) when is_list(Key) ->
                    Val = list_to_binary(Key),
                    Val = proplists:get_value(col1, Row);
                ({col7, Val0}) ->
                    Val = round(Val0 * 1.0e11),
                    Val = round(proplists:get_value(col7, Row) * 1.0e11);
                ({Key, Val}) -> 
                    Val = proplists:get_value(Key, Row)
            end, ReferenceRow)
    end, [Row1, Row2]),
    cqerl:close_client(Client).

get_client(Config) ->
    Host = proplists:get_value(host, Config),
    DataDir = proplists:get_value(data_dir, Config),

    %% To relative file paths for SSL, prepend the path of
    %% the test data directory. To bypass this behavior, provide
    %% an absolute path.

    SSL = case proplists:get_value(ssl, Config, undefined) of
        undefined -> false;
        false -> false;
        Options ->
            io:format("Options : ~w~n", [Options]),
            lists:map(fun
                ({FileOpt, Path}) when FileOpt == cacertfile;
                                       FileOpt == certfile;
                                       FileOpt == keyfile ->
                    case Path of
                        [$/ | _Rest] -> {FileOpt, Path};
                        _ -> {FileOpt, filename:join([DataDir, Path])}
                    end;
    
                (Opt) -> Opt
            end, Options)
    end,
    Auth = proplists:get_value(auth, Config, undefined),
    Keyspace = proplists:get_value(keyspace, Config),
    cqerl:new_client(Host, [{ssl, SSL}, {auth, Auth}, {keyspace, Keyspace}]).