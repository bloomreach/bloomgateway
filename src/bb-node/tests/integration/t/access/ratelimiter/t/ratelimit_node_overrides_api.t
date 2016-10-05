use setup;
no_shuffle;
run_tests;

__DATA__
=== RATELIMIT NODE OVERRIDES API TEST 1
Wait till start of next minute (init)
try (11) requests for (/) which is less than threshold value (12) for same
--- init
(my $sec,my $min) = localtime;
my $original_min = $min;
do
{
    sleep 1;
    ($sec, $min) = localtime;
}while( $min == $original_min );
--- pipelined_requests eval
["GET /", "GET /", "GET /", "GET /", "GET /", "GET /", "GET /", "GET /", "GET /", "GET /", "GET /"]
--- response_body eval
["ok\n", "ok\n", "ok\n", "ok\n", "ok\n", "ok\n", "ok\n", "ok\n", "ok\n", "ok\n", "ok\n"]

=== RATELIMIT NODE OVERRIDES API TEST 2
try (7) requests for (/api/v1/core) which is less than threshold value (9) for same
--- pipelined_requests eval
["GET /api/v1/core", "GET /api/v1/core", "GET /api/v1/core", "GET /api/v1/core", "GET /api/v1/core", "GET /api/v1/core", "GET /api/v1/core"]
--- response_body eval
["ok\n", "ok\n", "ok\n", "ok\n", "ok\n", "ok\n", "ok\n"]

=== RATELIMIT NODE OVERRIDES API TEST 3
try requests for api (/), should fail as node threshold value reached
--- request
GET /
--- response_body
Request threshold reached, please try again later
--- error_code : 429

=== RATELIMIT NODE OVERRIDES API TEST 4
try requests for api (/api/v1/core), should fail as node threshold value reached
--- request
GET /api/v1/core
--- response_body
Request threshold reached, please try again later
--- error_code : 429
