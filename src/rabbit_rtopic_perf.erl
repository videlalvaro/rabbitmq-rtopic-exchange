-module(rabbit_rtopic_perf).

-compile(export_all).

-include_lib("amqp_client/include/amqp_client.hrl").


test(NQs, QL) ->
    Runs = [{{10, 5}, 1},
            {{10, 5}, 10},
            {{10, 5}, 100},
            {{10, 5}, 1000},
            {{10, 5}, 10000}],
    
    run(<<"rtopic">>, NQs, QL, Runs).

run(XBin, NQs, QLen, Runs) ->
    prepare_bindings(XBin, NQs, QLen),
    F = fun ({N, L}) -> route(XBin, N, L) end,
    
    [begin
        Res = tcn(F, R, Reps),
        delete_exchange(XBin),
        Res
     end || {R, Reps} <- Runs].

prepare_bindings(XBin, N, Length) ->
    Queues = queues(N, Length),
    prepare_bindings0(XBin, Queues).

prepare_bindings0(XBin, Queues) ->
    [add_binding(XBin, Q, Q) || Q <- Queues],
    ok.

route(XBin, N, Length) ->
    RKeys = rkeys(N, Length),
    route0(XBin, RKeys).

route0(XBin, RKeys) ->
    Props = rabbit_basic:properties(#'P_basic'{content_type = <<"text/plain">>}),
    X = exchange(XBin),
    [begin
        Msg = rabbit_basic:message(XBin, RKey, Props, <<>>),
        Delivery = rabbit_basic:delivery(false, Msg, undefined),
        rabbit_exchange_type_rtopic:route(X, Delivery)
     end || RKey <- RKeys].

delete_exchange(XBin) ->
    X = exchange(XBin),
    F = fun () ->
            rabbit_exchange_type_rtopic:delete(transaction, X, [])
        end,
    rabbit_misc:execute_mnesia_transaction(F).

add_binding(XBin, QBin, BKey) ->
    F = fun () ->
            rabbit_exchange_type_rtopic:add_binding(transaction, exchange(XBin), binding(XBin, QBin, BKey))
        end,
    rabbit_misc:execute_mnesia_transaction(F).

dump_queues(N, Length) ->
    dump_to_file(N, Length, queues).

dump_rkeys(N, Length) ->
    dump_to_file(N, Length, rkeys).

dump_rand_rkeys(N, Length) ->
    dump_to_file(N, Length, rand_rkeys).

dump_to_file(N, Length, queues) ->
    Queues = queues(N, Length),
    dump_to_file("/tmp/queues", Queues);

dump_to_file(N, Length, rkeys) ->
    RKeys = rkeys(N, Length),
    dump_to_file("/tmp/rkeys", RKeys);

dump_to_file(N, Length, rand_rkeys) ->
    RKeys = rkeys_rand_len(N, Length),
    dump_to_file("/tmp/rand_rkeys", RKeys).

dump_to_file(F, Data) ->
    file:write_file(F, io_lib:fwrite("~p.\n", [Data])).

tc(F) ->
    B = now(), 
    F(), 
    A = now(), 
    timer:now_diff(A,B).

tcn(F, Arg, N) -> 
    B = now(), 
    tcn2(F, Arg, N), 
    A = now(), 
    timer:now_diff(A,B)/N.

tcn2(_F, _Arg, 0) -> ok; 
tcn2(F, Arg, N) -> 
    F(Arg), 
    tcn2(F, Arg, N-1).

queues(N, L) ->
    do_n(fun queue_name/1, L, N).

rkeys(N, L) ->
    do_n(fun routing_key/1, L, N).

rkeys_rand_len(N, L) ->
    do_n(fun rand_routing_key/1, L, N).

queue_name(L) ->
    list_to_binary(random_string(L, false)).

routing_key(L) ->
    list_to_binary(random_string(L, true)).

rand_routing_key(L) ->
    L1 = random:uniform(L),
    list_to_binary(random_string(L1, true)).

do_n(Fun, Arg, N) ->
    do_n(Fun, Arg, 0, N, []).

do_n(_Fun, _Arg, N, N, Acc) ->
    Acc;
do_n(Fun, Arg, Count, N, Acc) ->
    do_n(Fun, Arg, Count+1, N, [Fun(Arg) | Acc]).

random_string(0, _Wild) -> [];
random_string(1 = Length, Wild) -> [random_char(random:uniform(30), Wild) | random_string(Length-1, Wild)];
random_string(Length, Wild) -> [random_char(random:uniform(30), Wild), 46 | random_string(Length-1, Wild)].
random_char(1, true) -> 42;
random_char(2, true) -> 35;
random_char(_N, _) -> random:uniform(25) + 97.

exchange(XBin) ->
    #exchange{name        = #resource{virtual_host = <<"/">>, kind = exchange, name = XBin},
              type        = 'x-rtopic',
              durable     = true,
              auto_delete = false,
              arguments   = []}.

binding(XBin, QBin, BKey) ->
    #binding{source      = #resource{virtual_host = <<"/">>, kind = exchange, name = XBin},
             destination = #resource{virtual_host = <<"/">>, kind = queue, name = QBin},
             key         = BKey,
             args        = []}.